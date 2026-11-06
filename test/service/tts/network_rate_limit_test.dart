// Network rate-limit regression tests (problem C):
//
// Real-device symptom: entering a new chapter issued 5-6 simultaneous Aliyun
// synthesis requests (warm-up + `_prefetchAhead = 4`) and the gateway answered
// `400 {"status":40000005,"message":"Gateway:TOO_MANY_REQUESTS:Too many
// requests!"}`. The pipeline then retried every 120/240 ms (also rejected) and
// the user heard a 1.2-1.4 s gap.
//
// These tests cover the three layers of the fix:
// 1. `TtsSynthesisRequestGate`: concurrency bound, minimum start spacing,
//    slot release on exceptions, dispose/timeout cancellation.
// 2. `ProviderTtsSynthesisEngine`: real requests are queued through the gate,
//    request order is preserved, gateway rejections are mapped to
//    `isRateLimited`.
// 3. `OnlineTts`: rate-limited retries use the 600 ms/1500 ms exponential
//    backoff (injectable for determinism), generic errors keep ~120 ms, and a
//    prefetch rate-limit never stalls the queue.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anx_reader/service/tts/aliyun/aliyun_tts_backend.dart';
import 'package:anx_reader/service/tts/diagnostics/tts_diagnostics.dart';
import 'package:anx_reader/service/tts/engine/provider_tts_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String _rateLimitBody = '400 {"status":40000005,"message":'
    '"Gateway:TOO_MANY_REQUESTS:Too many requests!"}';

// ============ test doubles ============

/// Provider double whose server-side concurrency limit can be configured.
///
/// [rejectAboveConcurrency] models the Aliyun gateway: the (N+1)-th concurrent
/// request is rejected with the real `TOO_MANY_REQUESTS` body. The adapter's
/// gate is expected to make this branch unreachable.
class _FakeOnlineProvider extends TtsServiceProvider {
  _FakeOnlineProvider({
    this.maxConcurrentSynthesisRequests = 2,
    this.minSynthesisRequestInterval = Duration.zero,
    this.rejectAboveConcurrency,
    this.latency = const Duration(milliseconds: 5),
    this.errorForCall,
    this.maxRequestChars = 800,
  });

  @override
  TtsService get service => TtsService.aliyun;

  @override
  final int maxConcurrentSynthesisRequests;

  @override
  final Duration minSynthesisRequestInterval;

  @override
  final int maxRequestChars;

  /// Server-side concurrency limit (`null`: unlimited).
  final int? rejectAboveConcurrency;

  final Duration latency;
  final Object? Function(int callIndex)? errorForCall;

  final List<String> startedTexts = <String>[];
  final List<DateTime> startTimes = <DateTime>[];

  int _inFlight = 0;
  int maxObservedConcurrency = 0;
  int calls = 0;

  @override
  String getLabel(BuildContext context) => 'Fake online TTS';

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    calls += 1;
    _inFlight += 1;
    if (_inFlight > maxObservedConcurrency) maxObservedConcurrency = _inFlight;
    startedTexts.add(text);
    startTimes.add(DateTime.now());
    try {
      final error = errorForCall?.call(calls);
      if (error != null) throw error;
      final limit = rejectAboveConcurrency;
      if (limit != null && _inFlight > limit) {
        throw Exception('Aliyun TTS failed: $_rateLimitBody');
      }
      await Future<void>.delayed(latency);
      return Uint8List.fromList(const <int>[1, 2, 3]);
    } finally {
      _inFlight -= 1;
    }
  }
}

/// Synthesis engine double that can reject the first requests for a text with
/// a typed rate-limited failure.
class _RateLimitEngine implements TtsSynthesisEngine {
  _RateLimitEngine({
    Map<String, int>? failuresByText,
    this.nonRateLimited = false,
    this.maxRequestChars = 100,
  }) : _failuresByText = Map<String, int>.of(failuresByText ?? const {});

  final Map<String, int> _failuresByText;
  final bool nonRateLimited;
  final int maxRequestChars;

  final List<String> attempts = <String>[];

  int attemptsFor(String text) =>
      attempts.where((attempt) => attempt == text).length;

  @override
  TtsEngineKind get kind => TtsEngineKind.fake;

  @override
  String get engineId => 'fake';

  @override
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: kind,
        supportsNativePause: false,
        appliesRateOnServer: false,
        reportsCharacterProgress: false,
        maxRequestChars: maxRequestChars,
      );

  @override
  Future<Uint8List> synthesize(TtsSynthesisRequest request) async {
    attempts.add(request.text);
    await Future<void>.delayed(Duration.zero);
    final remaining = _failuresByText[request.text] ?? 0;
    if (remaining > 0) {
      _failuresByText[request.text] = remaining - 1;
      throw TtsEngineSynthesisException(
        engine: kind,
        message: nonRateLimited
            ? 'synthetic transient engine failure'
            : 'Gateway:TOO_MANY_REQUESTS:Too many requests!',
        isRateLimited: !nonRateLimited,
      );
    }
    return Uint8List.fromList(const <int>[1, 2, 3, 4]);
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {}
}

class _FakeAudioOutput implements TtsAudioOutput {
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  @override
  Future<void> initialize({bool warmUp = false}) async {}

  @override
  bool get supportsPreload => false;

  @override
  Future<void> prepare(TtsAudioRequest request) async {}

  @override
  bool get hasPrepared => false;

  @override
  Future<void> discardPrepared() async {}

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    scheduleMicrotask(() {
      if (!_completions.isClosed) _completions.add(null);
    });
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setPlaybackRate(double multiplier) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    await _completions.close();
  }
}

class _FakeTextSource implements TtsTextSource {
  _FakeTextSource(this.slices);

  final List<TtsTextSlice> slices;
  int _index = 0;

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    _index = 0;
    return slices.isEmpty ? null : slices.first;
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    final from = _index + 1;
    if (from >= slices.length) return const <TtsTextSlice>[];
    return slices.sublist(from, math.min(from + count, slices.length));
  }

  @override
  Future<TtsTextSlice?> advance() async {
    if (_index + 1 >= slices.length) return null;
    _index += 1;
    return slices[_index];
  }

  @override
  Future<TtsTextSlice?> rewind() async => null;

  @override
  Future<bool> isCfiVisible(String cfi) async => true;

  @override
  Future<String> currentPageToken() async => 'page-token';

  @override
  Future<void> clearHighlight() async {}

  @override
  Future<void> dispose() async {}
}

TtsSynthesisRequest _request(String text, {String? utteranceId}) {
  return TtsSynthesisRequest(
    text: text,
    config: const TtsSpeechConfig(rate: 1.0, pitch: 1.0, volume: 1.0),
    engine: TtsEngineKind.aliyun,
    utteranceId: utteranceId ?? 'u-$text',
  );
}

Future<OnlineTts> _newTts({
  required _RateLimitEngine engine,
  required List<TtsTextSlice> slices,
  int maxRetries = 2,
  Duration Function(int failedAttempt)? rateLimitBackoff,
}) async {
  final tts = OnlineTts.withDependencies(
    engineResolver: () => engine,
    audioOutputFactory: _FakeAudioOutput(),
    engineKindOverride: TtsEngineKind.fake,
    synthesisTimeout: const Duration(seconds: 1),
    maxRetries: maxRetries,
    rateLimitBackoff: rateLimitBackoff,
  );
  await tts.init(textSource: _FakeTextSource(slices));
  return tts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsSynthesisRequestGate', () {
    test('never admits more than maxConcurrentRequests at once', () async {
      final gate = TtsSynthesisRequestGate(maxConcurrentRequests: 2);
      var active = 0;
      var maxActive = 0;
      Future<void> worker() async {
        await gate.acquire();
        try {
          active += 1;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        } finally {
          active -= 1;
          gate.release();
        }
      }

      await Future.wait(<Future<void>>[for (var i = 0; i < 6; i++) worker()]);

      expect(maxActive, 2);
      expect(gate.activeRequests, 0);
      expect(gate.waitingRequests, 0);
      await gate.dispose();
    });

    test('admits waiters in FIFO order', () async {
      final gate = TtsSynthesisRequestGate(maxConcurrentRequests: 1);
      final order = <int>[];
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 5; i++)
          () async {
            await gate.acquire();
            try {
              order.add(i);
              await Future<void>.delayed(Duration.zero);
            } finally {
              gate.release();
            }
          }(),
      ]);
      expect(order, <int>[0, 1, 2, 3, 4]);
      await gate.dispose();
    });

    test('spaces request starts by minStartInterval', () async {
      final gate = TtsSynthesisRequestGate(
        maxConcurrentRequests: 4,
        minStartInterval: const Duration(milliseconds: 25),
      );
      final starts = <DateTime>[];
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 3; i++)
          () async {
            await gate.acquire();
            try {
              starts.add(DateTime.now());
            } finally {
              gate.release();
            }
          }(),
      ]);
      expect(starts, hasLength(3));
      for (var i = 1; i < starts.length; i++) {
        final gapMs = starts[i].difference(starts[i - 1]).inMilliseconds;
        expect(gapMs, greaterThanOrEqualTo(20),
            reason: 'starts $i and ${i - 1} were only ${gapMs}ms apart');
      }
      await gate.dispose();
    });

    test('releases the slot when the request throws', () async {
      final gate = TtsSynthesisRequestGate(maxConcurrentRequests: 1);

      Future<void> failingRequest() async {
        await gate.acquire();
        try {
          throw StateError('boom');
        } finally {
          gate.release();
        }
      }

      await expectLater(failingRequest(), throwsStateError);
      // The failed request must not keep the only slot: the next one proceeds.
      await gate.acquire().timeout(const Duration(milliseconds: 500));
      gate.release();
      expect(gate.activeRequests, 0);
      await gate.dispose();
    });

    test('times out a waiter instead of hanging forever', () async {
      final gate = TtsSynthesisRequestGate(
        maxConcurrentRequests: 1,
        acquireTimeout: const Duration(milliseconds: 40),
      );
      await gate.acquire();
      await expectLater(gate.acquire(), throwsA(isA<TimeoutException>()));
      expect(gate.waitingRequests, 0);
      gate.release();
      // The timed-out waiter did not leak the permit: a new request proceeds.
      await gate.acquire().timeout(const Duration(milliseconds: 500));
      gate.release();
      await gate.dispose();
    });

    test('dispose fails queued waiters instead of hanging them', () async {
      final gate = TtsSynthesisRequestGate(maxConcurrentRequests: 1);
      await gate.acquire();
      final waiting = gate.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(gate.waitingRequests, 1);

      // Attach the expectation before dispose so the failure is never an
      // unhandled asynchronous error.
      final waitingFailure = expectLater(
        waiting,
        throwsA(isA<TtsSynthesisGateClosedException>()),
      );
      await gate.dispose();

      await waitingFailure;
      expect(gate.waitingRequests, 0);
      expect(gate.isDisposed, isTrue);
      // In-flight release after dispose is harmless; new acquires are rejected.
      gate.release();
      await expectLater(
        gate.acquire(),
        throwsA(isA<TtsSynthesisGateClosedException>()),
      );
    });

    test('dispose cancels a pending inter-request timer', () async {
      final gate = TtsSynthesisRequestGate(
        maxConcurrentRequests: 2,
        minStartInterval: const Duration(seconds: 5),
      );
      await gate.acquire();
      final waiting = gate.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(gate.waitingRequests, 1);

      final waitingFailure = expectLater(
        waiting,
        throwsA(isA<TtsSynthesisGateClosedException>()),
      );
      await gate.dispose();

      await waitingFailure;
      gate.release();
    });
  });

  group('Aliyun backend rate-limit classification', () {
    test('recognises the gateway 40000005 / TOO_MANY_REQUESTS response', () {
      expect(
        AliyunTtsProvider.looksRateLimitedResponse(400, _rateLimitBody),
        isTrue,
      );
      expect(
        AliyunTtsProvider.looksRateLimitedResponse(429, 'Too Many Requests'),
        isTrue,
      );
      expect(
        AliyunTtsProvider.looksRateLimitedResponse(
          400,
          '{"status":40000009,"message":"Throttling.User"}',
        ),
        isTrue,
      );
    });

    test('keeps content/config/transport errors unflagged', () {
      expect(
        AliyunTtsProvider.looksRateLimitedResponse(
          400,
          '{"status":40000001,"message":"Invalid appkey"}',
        ),
        isFalse,
      );
      expect(
        AliyunTtsProvider.looksRateLimitedResponse(500, 'internal error'),
        isFalse,
      );
      expect(AliyunTtsProvider.looksRateLimitedResponse(200, ''), isFalse);
    });
  });

  group('ProviderTtsSynthesisEngine request gate', () {
    test('caps actual provider concurrency and preserves request order',
        () async {
      // The provider rejects anything above 2 concurrent requests, exactly like
      // the Aliyun gateway that produced the field error.
      final provider = _FakeOnlineProvider(
        maxConcurrentSynthesisRequests: 2,
        rejectAboveConcurrency: 2,
      );
      final engine = ProviderTtsSynthesisEngine(provider);
      final texts = <String>[for (var i = 0; i < 6; i++) '句子$i。'];

      final results = await Future.wait(
        <Future<Uint8List>>[
          for (final text in texts) engine.synthesize(_request(text)),
        ],
      );

      expect(results, hasLength(texts.length));
      expect(provider.maxObservedConcurrency, lessThanOrEqualTo(2),
          reason: 'the gate must keep the provider under its documented '
              'concurrency');
      expect(provider.startedTexts, texts,
          reason: 'FIFO admission must preserve the pipeline request order');
      expect(provider.calls, texts.length,
          reason: 'a correctly gated burst must not be rejected/retried');
      await engine.dispose();
    });

    test('honours the provider minimum request-start interval', () async {
      final provider = _FakeOnlineProvider(
        maxConcurrentSynthesisRequests: 2,
        minSynthesisRequestInterval: const Duration(milliseconds: 25),
      );
      final engine = ProviderTtsSynthesisEngine(provider);
      await Future.wait(<Future<Uint8List>>[
        for (var i = 0; i < 3; i++) engine.synthesize(_request('句子$i。')),
      ]);

      expect(provider.startTimes, hasLength(3));
      for (var i = 1; i < provider.startTimes.length; i++) {
        final gapMs = provider.startTimes[i]
            .difference(provider.startTimes[i - 1])
            .inMilliseconds;
        expect(gapMs, greaterThanOrEqualTo(20),
            reason: 'Aliyun needs a minimum start spacing; got ${gapMs}ms');
      }
      await engine.dispose();
    });

    test('maps the Aliyun gateway TOO_MANY_REQUESTS body to isRateLimited',
        () async {
      final provider = _FakeOnlineProvider(
        errorForCall: (_) => Exception('Aliyun TTS failed: $_rateLimitBody'),
      );
      final engine = ProviderTtsSynthesisEngine(provider);

      await expectLater(
        engine.synthesize(_request('句子。', utteranceId: 'para#1')),
        throwsA(
          isA<TtsEngineSynthesisException>()
              .having((e) => e.isRateLimited, 'isRateLimited', isTrue)
              .having((e) => e.isOversized, 'isOversized', isFalse)
              .having((e) => e.context['rateLimited'], 'context', 'true')
              .having((e) => e.context['utteranceId'], 'utteranceId', 'para#1')
              .having((e) => e.message, 'message', contains('TOO_MANY_REQUESTS'))
              .having((e) => e.toString(), 'toString',
                  contains('rateLimited: true')),
        ),
      );
      await engine.dispose();
    });

    test('maps a typed TtsRateLimitException and HTTP 429 messages', () async {
      final typedProvider = _FakeOnlineProvider(
        errorForCall: (_) => const TtsRateLimitException(
          message: 'Aliyun TTS rate limited',
          statusCode: 429,
        ),
      );
      final typedEngine = ProviderTtsSynthesisEngine(typedProvider);
      await expectLater(
        typedEngine.synthesize(_request('句子。')),
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
      );
      await typedEngine.dispose();

      final httpProvider = _FakeOnlineProvider(
        errorForCall: (_) => Exception('HTTP 429 Too Many Requests'),
      );
      final httpEngine = ProviderTtsSynthesisEngine(httpProvider);
      await expectLater(
        httpEngine.synthesize(_request('句子。')),
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
      );
      await httpEngine.dispose();
    });

    test('keeps non-rate-limit failures unflagged', () async {
      final provider = _FakeOnlineProvider(
        errorForCall: (_) => StateError('boom'),
      );
      final engine = ProviderTtsSynthesisEngine(provider);
      await expectLater(
        engine.synthesize(_request('句子。')),
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isFalse)
            .having((e) => e.cause, 'cause', isA<StateError>())),
      );
      await engine.dispose();
    });

    test('marks gateway rejections when the gate limit is bypassed', () async {
      // Deliberately misconfigured gate (10 concurrent) while the fake server
      // only accepts 2: this reproduces the raw field failure and proves the
      // provider error is classified as rate-limited (not a generic failure).
      final provider = _FakeOnlineProvider(
        maxConcurrentSynthesisRequests: 10,
        rejectAboveConcurrency: 2,
        latency: const Duration(milliseconds: 20),
      );
      final engine = ProviderTtsSynthesisEngine(provider);
      final errors = <Object>[];
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 6; i++)
          engine.synthesize(_request('句子$i。')).then<void>(
                (_) {},
                onError: (Object error) => errors.add(error),
              ),
      ]);

      expect(provider.maxObservedConcurrency, greaterThan(2),
          reason: 'the ungated burst must trip the fake gateway');
      expect(errors, isNotEmpty);
      final typedErrors = errors.whereType<TtsEngineSynthesisException>();
      expect(typedErrors, hasLength(errors.length));
      expect(typedErrors.every((e) => e.isRateLimited), isTrue,
          reason: 'all gateway TOO_MANY_REQUESTS rejections are rate limited');
      await engine.dispose();
    });

    test('oversized and blank validation never occupies a gate slot',
        () async {
      final provider = _FakeOnlineProvider(
        maxConcurrentSynthesisRequests: 1,
        maxRequestChars: 100,
        latency: const Duration(milliseconds: 200),
      );
      final engine = ProviderTtsSynthesisEngine(provider);

      // Oversized: typed validation error, provider/network untouched.
      await expectLater(
        engine.synthesize(_request('字' * 400)),
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.isOversized, 'isOversized', isTrue)),
      );
      expect(engine.requestGate.activeRequests, 0);
      expect(engine.requestGate.waitingRequests, 0);

      // Blank: silent segment, no request and no slot.
      final blank = await engine.synthesize(_request('   '));
      expect(blank, isEmpty);
      expect(engine.requestGate.activeRequests, 0);
      expect(provider.calls, 0);

      // A real request still gets the only slot immediately.
      final realBytes = await engine.synthesize(_request('句子。'));
      expect(realBytes, isNotEmpty);
      await engine.dispose();
    });

    test('dispose fails queued waiters and keeps the adapter reusable',
        () async {
      final provider = _FakeOnlineProvider(
        maxConcurrentSynthesisRequests: 1,
        latency: const Duration(milliseconds: 100),
      );
      final engine = ProviderTtsSynthesisEngine(provider);

      final inFlight = engine.synthesize(_request('第一句。'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final queued = engine.synthesize(_request('第二句。'));
      await Future<void>.delayed(Duration.zero);
      expect(engine.requestGate.waitingRequests, 1);

      // Attach the expectation before dispose so the cancelled waiter is never
      // reported as an unhandled asynchronous error.
      final queuedFailure = expectLater(
        queued,
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.cause,
                'cause', isA<TtsSynthesisGateClosedException>())),
      );
      final inFlightCompletion = expectLater(inFlight, completes);
      await engine.dispose();

      await queuedFailure;
      // The in-flight request keeps its (old) slot and settles normally.
      await inFlightCompletion;

      // Shared providers stay usable: a fresh gate serves later requests.
      final bytes = await engine.synthesize(_request('第三句。'));
      expect(bytes, isNotEmpty);
      await engine.dispose();
    });
  });

  group('OnlineTts rate-limit retry backoff', () {
    const List<TtsTextSlice> slices = <TtsTextSlice>[
      TtsTextSlice(text: '第一句。', cfi: 'cfi-0', index: 0),
      TtsTextSlice(text: '第二句。', cfi: 'cfi-1', index: 1),
    ];

    test('production schedule is ~600ms then ~1500ms with ±100ms jitter', () {
      final random = math.Random(7);
      for (var i = 0; i < 50; i++) {
        final first =
            OnlineTts.rateLimitRetryDelay(0, random: random).inMilliseconds;
        expect(first, inInclusiveRange(500, 700));
        final second =
            OnlineTts.rateLimitRetryDelay(1, random: random).inMilliseconds;
        expect(second, inInclusiveRange(1400, 1600));
      }
      // A rate-limit schedule longer than the generic 120ms retry is the point.
      expect(OnlineTts.rateLimitRetrySchedule.first,
          greaterThan(const Duration(milliseconds: 120)));
      expect(OnlineTts.rateLimitRetrySchedule[1],
          greaterThan(OnlineTts.rateLimitRetrySchedule.first));
    });

    test('rate-limited retries use the backoff sequence and then succeed',
        () async {
      final engine = _RateLimitEngine(
        failuresByText: <String, int>{'第一句。': 2},
      );
      final backoffAttempts = <int>[];
      final tts = await _newTts(
        engine: engine,
        slices: slices,
        maxRetries: 2,
        rateLimitBackoff: (failedAttempt) {
          backoffAttempts.add(failedAttempt);
          return const Duration(milliseconds: 1);
        },
      );

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.hasError, isFalse);
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
      expect(backoffAttempts, <int>[0, 1],
          reason: 'first rate-limit retry 600ms, second 1500ms schedule');
      expect(engine.attemptsFor('第一句。'), 3,
          reason: 'two rate-limited failures, third attempt succeeds');
      expect(engine.attemptsFor('第二句。'), 1);
      // The rate-limit class is visible in the diagnostic event.
      final failures = tts.ttsDiagnostics.whereType<TtsSynthesisFailed>();
      expect(failures, isNotEmpty);
      expect(failures.first.error, startsWith('rate-limited:'));
    });

    test('exhausted rate-limited retries surface a typed retryable error',
        () async {
      final engine = _RateLimitEngine(
        failuresByText: <String, int>{'第一句。': 10},
      );
      final backoffAttempts = <int>[];
      final tts = await _newTts(
        engine: engine,
        slices: slices,
        maxRetries: 2,
        rateLimitBackoff: (failedAttempt) {
          backoffAttempts.add(failedAttempt);
          return const Duration(milliseconds: 1);
        },
      );

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.phase, TtsPlaybackPhase.error);
      final error = tts.playbackState.error;
      expect(error, isA<TtsSynthesisError>());
      expect(error!.retryable, isTrue);
      expect(backoffAttempts, <int>[0, 1]);
      expect(engine.attemptsFor('第一句。'), 3,
          reason: 'retry count is unchanged (maxRetries + 1 attempts)');
    });

    test('a prefetch rate-limit does not stall the playback queue', () async {
      // The second slice is prefetched ahead; its first two attempts are
      // rate-limited. The playback path shares the same single-flight future
      // and must continue after the backoff instead of deadlocking.
      final engine = _RateLimitEngine(
        failuresByText: <String, int>{'第二句。': 2},
      );
      final tts = await _newTts(
        engine: engine,
        slices: slices,
        maxRetries: 2,
        rateLimitBackoff: (_) => const Duration(milliseconds: 1),
      );

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.hasError, isFalse);
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
      expect(engine.attemptsFor('第二句。'), 3,
          reason: 'prefetch retried with the rate-limit backoff');
      expect(engine.attemptsFor('第一句。'), 1);
    });

    test('non-rate-limit errors keep the short ~120ms retry', () async {
      final engine = _RateLimitEngine(
        failuresByText: <String, int>{'第一句。': 1},
        nonRateLimited: true,
      );
      final tts = await _newTts(
        engine: engine,
        slices: slices,
        maxRetries: 1,
      );

      final stopwatch = Stopwatch()..start();
      await tts.speak();
      await tts.currentSession;
      stopwatch.stop();

      expect(tts.playbackState.hasError, isFalse);
      expect(engine.attemptsFor('第一句。'), 2);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: 'generic retry delay stays 120ms, not the 600ms+ schedule');
    });

    test('audible gap log thresholds: INFO up to 2500ms, SEVERE above',
        () {
      expect(OnlineTts.audibleGapInfoThresholdMs, 600);
      expect(OnlineTts.audibleGapSevereThresholdMs, 2500);
      for (final gapMs in <int>[0, 599, 600, 601, 1191, 1433, 2500]) {
        expect(OnlineTts.isSevereAudibleGap(gapMs), isFalse,
            reason: '${gapMs}ms is realistic chapter-start latency');
      }
      for (final gapMs in <int>[2501, 4000]) {
        expect(OnlineTts.isSevereAudibleGap(gapMs), isTrue);
      }
    });
  });
}
