// Controllable audio output double for the round-2 regression harness.
//
// Two modes:
// - autoComplete (default): a started segment completes after
//   [segmentDuration] of *virtual* time, so the pipeline's queue/prefetch
//   behaviour can be measured deterministically;
// - manual: the test completes the current segment with [completeCurrent],
//   which is required to prove pause/resume does not advance or skip text.
//
// Every call is recorded in the shared [Round2EventLog] with virtual
// timestamps, so ordering across engine -> page turn -> next segment is
// asserted on one timeline.

import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';

import 'round2_clock.dart';
import 'round2_event_log.dart';

class Round2AudioStart {
  const Round2AudioStart({
    required this.utteranceId,
    required this.bytes,
    required this.playbackRate,
    required this.applyRate,
    required this.atMs,
  });

  final String utteranceId;
  final Uint8List bytes;
  final double playbackRate;
  final bool applyRate;
  final int atMs;

  @override
  String toString() =>
      'start($utteranceId, rate: $playbackRate, applyRate: $applyRate, '
      '@${atMs}ms)';
}

class Round2AudioOutput implements TtsAudioOutput {
  Round2AudioOutput({
    required this.scheduler,
    required this.log,
    this.autoComplete = true,
    this.segmentDuration = const Duration(milliseconds: 640),
    this.supportsPreload = true,
  });

  final Round2Scheduler scheduler;
  final Round2EventLog log;
  final Duration segmentDuration;

  /// Whether [start] schedules its own completion on the virtual timeline.
  /// When false the test controls completion with [completeCurrent].
  bool autoComplete;

  @override
  final bool supportsPreload;

  Round2Clock get clock => scheduler.clock;

  final List<Round2AudioStart> starts = <Round2AudioStart>[];
  final List<double> playbackRateChanges = <double>[];
  final List<double> volumes = <double>[];
  final List<bool> warmUpCalls = <bool>[];

  TtsAudioRequest? preparedRequest;
  bool hasPreparedValue = false;
  bool paused = false;
  bool playing = false;
  bool disposed = false;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  int discardCalls = 0;
  int initializeCalls = 0;

  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  int _completionToken = 0;

  List<String> get startedUtteranceIds =>
      starts.map((start) => start.utteranceId).toList(growable: false);

  List<int> get startedAtMs => starts.map((start) => start.atMs).toList();

  List<double> get startedRates =>
      starts.map((start) => start.playbackRate).toList();

  List<bool> get appliedRateFlags =>
      starts.map((start) => start.applyRate).toList();

  @override
  Future<void> initialize({bool warmUp = false}) async {
    initializeCalls += 1;
    warmUpCalls.add(warmUp);
  }

  @override
  Future<void> prepare(TtsAudioRequest request) async {
    preparedRequest = request;
    hasPreparedValue = true;
    log.add(
      Round2EventKind.audioPrepared,
      clock: clock,
      label: request.utteranceId ?? '',
    );
  }

  @override
  bool get hasPrepared => hasPreparedValue;

  @override
  Future<void> discardPrepared() async {
    discardCalls += 1;
    hasPreparedValue = false;
    preparedRequest = null;
  }

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    final request = preparedRequest;
    final start = Round2AudioStart(
      utteranceId: request?.utteranceId ?? '',
      bytes: request?.bytes ?? Uint8List(0),
      playbackRate: playbackRate,
      applyRate: applyRate,
      atMs: clock.ms,
    );
    starts.add(start);
    preparedRequest = null;
    hasPreparedValue = false;
    playing = true;
    paused = false;
    log.add(
      Round2EventKind.audioStarted,
      clock: clock,
      label: start.utteranceId,
      data: <String, Object?>{
        'rate': playbackRate,
        'applyRate': applyRate,
        'bytes': start.bytes.length,
        'startIndex': starts.length - 1,
      },
    );
    if (autoComplete) {
      _scheduleCompletion();
    }
  }

  void _scheduleCompletion() {
    final token = ++_completionToken;
    final startIndex = starts.length - 1;
    unawaited(scheduler.delay(segmentDuration).then((_) {
      if (token != _completionToken || paused || disposed) return;
      playing = false;
      log.add(
        Round2EventKind.audioCompleted,
        clock: clock,
        data: <String, Object?>{'startIndex': startIndex},
      );
      if (!_completions.isClosed) _completions.add(null);
    }));
  }

  /// Completes the currently playing segment manually (manual mode).
  void completeCurrent() {
    if (disposed || _completions.isClosed) return;
    playing = false;
    log.add(
      Round2EventKind.audioCompleted,
      clock: clock,
      data: <String, Object?>{'startIndex': starts.length - 1},
    );
    _completions.add(null);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    paused = true;
    // A scheduled completion of a paused segment is not delivered: real audio
    // output fires completion only after the segment has actually finished.
    _completionToken += 1;
    log.add(Round2EventKind.audioPaused, clock: clock);
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    paused = false;
    log.add(Round2EventKind.audioResumed, clock: clock);
    if (autoComplete && playing) {
      _scheduleCompletion();
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playing = false;
    paused = false;
    _completionToken += 1;
    log.add(Round2EventKind.audioStopped, clock: clock);
  }

  @override
  Future<void> setPlaybackRate(double multiplier) async {
    playbackRateChanges.add(multiplier);
    log.add(
      Round2EventKind.note,
      clock: clock,
      label: 'playbackRateChange',
      data: <String, Object?>{'multiplier': multiplier},
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    _completionToken += 1;
    if (!_completions.isClosed) await _completions.close();
  }
}
