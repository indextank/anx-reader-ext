// Recording synthesis engine with per-service latency/concurrency profiles.
//
// The profiles reproduce the field behaviour that makes the round-2 bugs
// reproducible without network access:
// - Aliyun: documented 300-char request limit, server-side rate parameter,
//   moderate latency, a small amount of request parallelism.
// - MiMo: no server-side rate parameter (rate is applied by the audio player),
//   slow responses and a strict single-request limit, which is what turns a
//   missing prefetch into the reported "playback stops after the next line
//   while it waits for the next synthesis" symptom.
// - StepAudio: 1000-char requests, server-side rate, a single in-flight request
//   and fairly high latency, which reproduces the perceptible stall right
//   before the next paragraph starts when the pipeline serialises
//   synthesis with playback.
//
// Requests are recorded with virtual requested/completed timestamps so tests
// can assert queueing behaviour (max observed concurrency) and per-segment
// latency deterministically.

import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

import 'round2_clock.dart';
import 'round2_event_log.dart';

/// Latency/concurrency characteristics of one cloud engine.
class Round2EngineProfile {
  const Round2EngineProfile({
    required this.name,
    required this.kind,
    required this.maxRequestChars,
    required this.appliesRateOnServer,
    required this.synthesisLatency,
    required this.maxParallelRequests,
    this.rejectOversize = false,
  });

  final String name;
  final TtsEngineKind kind;
  final int maxRequestChars;
  final bool appliesRateOnServer;

  /// Virtual time a single synthesis request takes.
  final Duration synthesisLatency;

  /// Maximum concurrent synthesis requests the service accepts. Additional
  /// requests are queued (modelled as added latency), like the real providers.
  final int maxParallelRequests;

  /// Throw a typed oversized exception when the request exceeds
  /// [maxRequestChars] (models the provider HTTP 400).
  final bool rejectOversize;

  static const Round2EngineProfile aliyun = Round2EngineProfile(
    name: 'aliyun',
    kind: TtsEngineKind.aliyun,
    maxRequestChars: 300,
    appliesRateOnServer: true,
    synthesisLatency: Duration(milliseconds: 320),
    maxParallelRequests: 2,
    rejectOversize: true,
  );

  static const Round2EngineProfile mimo = Round2EngineProfile(
    name: 'mimo',
    kind: TtsEngineKind.mimo,
    maxRequestChars: 800,
    appliesRateOnServer: false,
    synthesisLatency: Duration(milliseconds: 450),
    maxParallelRequests: 1,
  );

  static const Round2EngineProfile stepAudio = Round2EngineProfile(
    name: 'stepAudio',
    kind: TtsEngineKind.stepAudio,
    maxRequestChars: 1000,
    appliesRateOnServer: true,
    synthesisLatency: Duration(milliseconds: 380),
    maxParallelRequests: 1,
  );

  /// Native system engine has no synthesis requests; modelled separately by
  /// the fake native engine, but the profile keeps the matrix uniform.
  static const Round2EngineProfile system = Round2EngineProfile(
    name: 'system',
    kind: TtsEngineKind.system,
    maxRequestChars: 4000,
    appliesRateOnServer: false,
    synthesisLatency: Duration.zero,
    maxParallelRequests: 1,
  );

  static const List<Round2EngineProfile> cloudEngines = <Round2EngineProfile>[
    aliyun,
    mimo,
    stepAudio,
  ];
}

class Round2SynthesisRecord {
  Round2SynthesisRecord({
    required this.request,
    required this.requestedAtMs,
    required this.sequence,
  });

  final TtsSynthesisRequest request;
  final int requestedAtMs;
  final int sequence;

  int? completedAtMs;

  String get text => request.text;

  int get latencyMs => (completedAtMs ?? requestedAtMs) - requestedAtMs;
}

/// [TtsSynthesisEngine] double that records requests and emulates the profile
/// above through the shared [Round2Scheduler].
class Round2RecordingEngine implements TtsSynthesisEngine {
  Round2RecordingEngine({
    required this.profile,
    required this.scheduler,
    required this.log,
    this.bytesPerChar = 4,
  });

  final Round2EngineProfile profile;
  final Round2Scheduler scheduler;
  final Round2EventLog log;
  final int bytesPerChar;

  final List<TtsSynthesisRequest> requests = <TtsSynthesisRequest>[];
  final List<Round2SynthesisRecord> records = <Round2SynthesisRecord>[];

  int _inFlight = 0;
  int maxObservedParallel = 0;
  int _sequence = 0;
  int disposeCalls = 0;

  Round2Clock get clock => scheduler.clock;

  List<String> get requestTexts =>
      requests.map((request) => request.text).toList(growable: false);

  String get joinedTexts => requestTexts.join();

  int get maxRequestChars => profile.maxRequestChars;

  @override
  TtsEngineKind get kind => profile.kind;

  @override
  String get engineId => 'round2-${profile.name}';

  @override
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: profile.kind,
        supportsNativePause: false,
        appliesRateOnServer: profile.appliesRateOnServer,
        reportsCharacterProgress: false,
        maxRequestChars: profile.maxRequestChars,
      );

  @override
  Future<Uint8List> synthesize(TtsSynthesisRequest request) async {
    final record = Round2SynthesisRecord(
      request: request,
      requestedAtMs: clock.ms,
      sequence: _sequence++,
    );
    records.add(record);
    log.add(
      Round2EventKind.synthesisRequested,
      clock: clock,
      label: request.text,
      data: <String, Object?>{
        'engine': profile.name,
        'chars': request.text.length,
        'rate': request.config.rate,
        'utterance': request.utteranceId ?? '',
      },
    );

    _inFlight += 1;
    if (_inFlight > maxObservedParallel) maxObservedParallel = _inFlight;
    try {
      // Serialise beyond the provider's parallel limit: the extra request waits
      // for a second virtual round-trip.
      var latency = profile.synthesisLatency;
      if (_inFlight > profile.maxParallelRequests) {
        latency += profile.synthesisLatency;
      }
      await scheduler.delay(latency);

      if (profile.rejectOversize &&
          request.text.length > profile.maxRequestChars) {
        record.completedAtMs = clock.ms;
        log.add(
          Round2EventKind.synthesisFailed,
          clock: clock,
          label: request.text,
          data: <String, Object?>{'engine': profile.name, 'oversized': true},
        );
        throw TtsEngineSynthesisException(
          engine: profile.kind,
          message: 'request exceeds ${profile.maxRequestChars} characters',
          isOversized: true,
          context: <String, String>{
            'engine': profile.name,
            'chars': '${request.text.length}',
            'limit': '${profile.maxRequestChars}',
          },
        );
      }

      record.completedAtMs = clock.ms;
      requests.add(request);
      log.add(
        Round2EventKind.synthesisCompleted,
        clock: clock,
        label: request.text,
        data: <String, Object?>{
          'engine': profile.name,
          'latencyMs': record.latencyMs,
          'utterance': request.utteranceId ?? '',
        },
      );
      return Uint8List.fromList(
        List<int>.generate(request.text.length * bytesPerChar, (i) => i % 251),
      );
    } finally {
      _inFlight -= 1;
    }
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
