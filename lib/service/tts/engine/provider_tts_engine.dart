import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/engine/engine_kind_mapping.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';

/// Raised to a caller still waiting for a synthesis slot when the owning
/// engine/session is disposed. Waiting must never hang a playback
/// continuation: a stopped session has no reason to keep a synthesis future
/// alive.
class TtsSynthesisGateClosedException implements Exception {
  const TtsSynthesisGateClosedException([
    this.message = 'The synthesis request gate was disposed',
  ]);

  final String message;

  @override
  String toString() => 'TtsSynthesisGateClosedException($message)';
}

/// Admission gate for cloud synthesis requests.
///
/// The playback pipeline intentionally overlaps requests (cold-start warm-up
/// plus a `prefetchAhead = 4` lookahead window), so entering a new chapter can
/// produce 5-6 simultaneous synthesis calls. Aliyun's gateway rejects exactly
/// that burst with `400 {"status":40000005,"message":
/// "Gateway:TOO_MANY_REQUESTS:Too many requests!"}`; the subsequent tight
/// retries (120/240 ms) also fail and the user hears a 1.2-1.4 s gap.
///
/// This gate is the single serialization point for real network requests:
///
/// - at most [maxConcurrentRequests] requests are in flight,
/// - two request *starts* are spaced by at least [minStartInterval],
/// - waiters are admitted in FIFO order (the pipeline keeps its request order),
/// - [dispose] fails queued waiters instead of leaving them hanging.
///
/// The oversize/blank validation of [ProviderTtsSynthesisEngine.synthesize]
/// runs before the gate, so rejected no-op requests never consume a slot.
class TtsSynthesisRequestGate {
  TtsSynthesisRequestGate({
    this.maxConcurrentRequests = 2,
    this.minStartInterval = Duration.zero,
    this.acquireTimeout = const Duration(seconds: 20),
  })  : assert(maxConcurrentRequests > 0,
            'maxConcurrentRequests must be positive'),
        assert(!minStartInterval.isNegative,
            'minStartInterval must not be negative');

  /// Maximum number of concurrent requests admitted by the gate.
  final int maxConcurrentRequests;

  /// Minimum time between two request starts. Zero disables spacing.
  final Duration minStartInterval;

  /// Safety bound so a caller can never wait forever even if a request never
  /// settles (the provider HTTP client has no cancellation support).
  final Duration acquireTimeout;

  final Queue<_SynthesisGateWaiter> _waiters = Queue<_SynthesisGateWaiter>();

  int _activeRequests = 0;
  DateTime? _lastStartAt;
  Timer? _pumpTimer;
  bool _disposed = false;

  /// Number of requests currently holding a slot.
  int get activeRequests => _activeRequests;

  /// Number of requests waiting for a slot.
  int get waitingRequests => _waiters.length;

  bool get isDisposed => _disposed;

  /// Waits until a request slot is free and the minimum start spacing elapsed.
  ///
  /// The caller must call [release] exactly once after the request settles
  /// (use `try/finally`). Throws [TtsSynthesisGateClosedException] when the
  /// gate was disposed, and [TimeoutException] when [acquireTimeout] expires.
  Future<void> acquire() {
    if (_disposed) {
      return Future<void>.error(const TtsSynthesisGateClosedException());
    }
    final waiter = _SynthesisGateWaiter();
    _waiters.add(waiter);
    _pump();
    return waiter.completer.future.timeout(acquireTimeout, onTimeout: () {
      // The gate never admitted the waiter: remove it so a later pump cannot
      // leak a permit to an abandoned caller.
      if (!waiter.admitted) {
        waiter.cancelled = true;
        _waiters.remove(waiter);
      }
      throw TimeoutException(
        'Timed out waiting for a synthesis slot after '
        '${acquireTimeout.inMilliseconds}ms',
        acquireTimeout,
      );
    });
  }

  /// Releases one request slot. Safe to call once per successful [acquire];
  /// ignored when the gate already admitted nothing (defensive).
  void release() {
    if (_activeRequests > 0) _activeRequests -= 1;
    _pump();
  }

  /// Fails every queued waiter with [TtsSynthesisGateClosedException].
  ///
  /// In-flight requests keep their slot: an HTTP request cannot be cancelled,
  /// so the gate merely refuses new and queued work. The owner disposes the
  /// gate when a session/engine goes away.
  Future<void> dispose() async {
    _disposed = true;
    _pumpTimer?.cancel();
    _pumpTimer = null;
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.admitted) {
        waiter.completer.completeError(
          const TtsSynthesisGateClosedException(),
        );
      }
    }
  }

  void _pump() {
    if (_disposed) return;
    _pumpTimer?.cancel();
    _pumpTimer = null;
    while (_waiters.isNotEmpty && _activeRequests < maxConcurrentRequests) {
      final wait = _timeUntilNextStart();
      if (wait > Duration.zero) {
        _pumpTimer = Timer(wait, () {
          _pumpTimer = null;
          _pump();
        });
        return;
      }
      final waiter = _waiters.removeFirst();
      if (waiter.cancelled || waiter.admitted) continue;
      _activeRequests += 1;
      _lastStartAt = DateTime.now();
      waiter.admitted = true;
      waiter.completer.complete();
    }
  }

  Duration _timeUntilNextStart() {
    if (minStartInterval == Duration.zero) return Duration.zero;
    final lastStartAt = _lastStartAt;
    if (lastStartAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(lastStartAt);
    if (elapsed >= minStartInterval) return Duration.zero;
    return minStartInterval - elapsed;
  }
}

final class _SynthesisGateWaiter {
  final Completer<void> completer = Completer<void>();
  bool admitted = false;
  bool cancelled = false;
}

/// [TtsSynthesisEngine] adapter for the cloud [TtsServiceProvider]s
/// (Aliyun, Azure, OpenAI, StepAudio, MiMo).
///
/// It is the single place where the pipeline's per-request contract is
/// enforced:
/// - blank text resolves to empty bytes (a silent segment, no request),
/// - text above [TtsServiceProvider.maxRequestChars] throws the shared
///   [TtsEngineSynthesisException] with `isOversized: true`, so the pipeline
///   can split the utterance instead of losing it (the Aliyun 300-character
///   paragraph-skip root cause),
/// - real network requests pass through [TtsSynthesisRequestGate] (provider
///   concurrency bound + minimum request-start spacing), so the warm-up /
///   prefetch burst can no longer trip a gateway rate limit,
/// - provider failures are wrapped into the same typed exception so the
///   pipeline can surface a retryable error with the engine id and request
///   context. Gateway rate limits (`TOO_MANY_REQUESTS`, Aliyun `40000005`,
///   HTTP 429) are flagged with `isRateLimited: true` so the playback pipeline
///   can use its exponential backoff instead of the short generic retry.
///
/// The adapter owns no network resources: the underlying providers are
/// app-wide singletons that keep HTTP clients and token caches. [dispose] only
/// releases the request gate (failing queued waiters) and replaces it so a
/// later resolution can keep using the shared provider.
class ProviderTtsSynthesisEngine implements TtsSynthesisEngine {
  /// Wraps [provider] in the pipeline engine contract.
  ///
  /// [requestGate] is injectable for tests; production resolves it from
  /// [TtsServiceProvider.maxConcurrentSynthesisRequests] and
  /// [TtsServiceProvider.minSynthesisRequestInterval].
  ///
  /// Throws [ArgumentError] when [provider] does not expose a [TtsService],
  /// which would make the engine kind/capabilities ambiguous.
  ProviderTtsSynthesisEngine(
    TtsServiceProvider provider, {
    TtsSynthesisRequestGate? requestGate,
  }) : this._(
          provider,
          _kindOf(provider),
          requestGate ?? _gateForProvider(provider),
        );

  ProviderTtsSynthesisEngine._(this.provider, this.kind, this._requestGate);

  /// Resolves a provider through [TtsService.provider], unless [provider] is
  /// supplied explicitly (tests, or a specially configured instance).
  factory ProviderTtsSynthesisEngine.forService(
    TtsService service, {
    TtsServiceProvider? provider,
    TtsSynthesisRequestGate? requestGate,
  }) {
    return ProviderTtsSynthesisEngine(
      provider ?? service.provider,
      requestGate: requestGate,
    );
  }

  /// Resolves the provider from a persisted service id (`aliyun`, `mimo`,
  /// `stepaudio`, ...). Unknown ids fall back to the system service, matching
  /// [getTtsService].
  factory ProviderTtsSynthesisEngine.forServiceId(
    String serviceId, {
    TtsServiceProvider? provider,
    TtsSynthesisRequestGate? requestGate,
  }) {
    final service = getTtsService(serviceId);
    return ProviderTtsSynthesisEngine(
      provider ?? service.provider,
      requestGate: requestGate,
    );
  }

  final TtsServiceProvider provider;

  /// Typed engine identity, derived from the wrapped provider.
  @override
  final TtsEngineKind kind;

  TtsSynthesisRequestGate _requestGate;

  /// The gate currently serializing real requests (may be replaced by
  /// [dispose]).
  TtsSynthesisRequestGate get requestGate => _requestGate;

  /// Stable engine id (`system`, `aliyun`, `mimo`, ...).
  @override
  String get engineId => provider.serviceId;

  /// Documentation evidence for [TtsEngineCapabilities.maxRequestChars].
  String get documentedRequestLimitNote => provider.documentedRequestLimitNote;

  /// Capabilities are derived from the provider getters so the pipeline has
  /// one source of truth per engine (no `is` checks on concrete backends).
  @override
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: kind,
        supportsNativePause: provider.supportsNativePause,
        appliesRateOnServer: provider.supportsRateParameter,
        reportsCharacterProgress: provider.reportsCharacterProgress,
        maxRequestChars: provider.maxRequestChars,
      );

  @override
  Future<Uint8List> synthesize(TtsSynthesisRequest request) async {
    final text = request.text;

    // Blank text is a silent segment. Match the providers' own semantics and
    // skip the request entirely (no config/network work either, and no gate
    // slot: a silent segment must never delay a real request).
    if (text.trim().isEmpty) {
      return Uint8List(0);
    }

    final maxChars = capabilities.maxRequestChars;
    // A non-positive limit means "no limit" (see splitTtsParagraph): engines
    // never set it, but the adapter stays consistent for test engines.
    if (maxChars > 0 && text.length > maxChars) {
      // Validation failure, not a network request: stays outside the gate so
      // a split/retry never waits behind real requests.
      throw TtsEngineSynthesisException(
        engine: kind,
        message: '$engineId accepts at most $maxChars characters per request; '
            'got ${text.length} characters',
        isOversized: true,
        context: <String, String>{
          'maxRequestChars': '$maxChars',
          'textLength': '${text.length}',
          'limitNote': documentedRequestLimitNote,
          if (request.utteranceId != null) 'utteranceId': request.utteranceId!,
        },
      );
    }

    final gate = _requestGate;
    var holdsGate = false;
    try {
      await gate.acquire();
      holdsGate = true;
      return await provider.speak(
        text,
        request.config.voice,
        request.config.rate,
        request.config.pitch,
      );
    } on TtsEngineSynthesisException {
      // A provider must not throw this type, but if one ever does keep the
      // typed information instead of nesting it inside another exception.
      rethrow;
    } catch (error) {
      final rateLimited = isRateLimitError(error);
      throw TtsEngineSynthesisException(
        engine: kind,
        message: '$engineId synthesis failed: $error',
        cause: error,
        isRateLimited: rateLimited,
        context: <String, String>{
          'textLength': '${text.length}',
          if (rateLimited) 'rateLimited': 'true',
          if (request.config.voice != null) 'voice': request.config.voice!,
          if (request.utteranceId != null) 'utteranceId': request.utteranceId!,
        },
      );
    } finally {
      if (holdsGate) gate.release();
    }
  }

  /// Whether [error] thrown by a provider means "the gateway rejected this
  /// request because too many arrived" rather than a content/config failure.
  ///
  /// The real Aliyun sample is a typed [TtsRateLimitException], but the HTTP
  /// client and older provider code can also surface raw messages; matching the
  /// documented markers keeps the classification robust across providers.
  static bool isRateLimitError(Object? error) {
    if (error == null) return false;
    if (error is TtsRateLimitException) return true;
    final message =
        error is TtsEngineSynthesisException ? error.message : '$error';
    final upper = message.toUpperCase();
    if (upper.contains('TOO_MANY_REQUESTS') ||
        upper.contains('40000005') ||
        upper.contains('THROTTLING')) {
      return true;
    }
    return _status429Pattern.hasMatch(message);
  }

  static final RegExp _status429Pattern = RegExp(r'(?<![0-9])429(?![0-9])');

  @override
  Future<List<TtsVoice>> voices() => provider.getVoices();

  @override
  Future<void> dispose() async {
    // Providers are shared app-wide singletons; the adapter owns only the
    // request gate. Fail queued waiters (a stopped session must never leave a
    // synthesis continuation hanging), then install a fresh gate so a later
    // resolution of the shared adapter stays usable.
    final gate = _requestGate;
    _requestGate = _gateForProvider(provider);
    await gate.dispose();
  }

  static TtsSynthesisRequestGate _gateForProvider(
    TtsServiceProvider provider,
  ) {
    return TtsSynthesisRequestGate(
      maxConcurrentRequests: provider.maxConcurrentSynthesisRequests,
      minStartInterval: provider.minSynthesisRequestInterval,
    );
  }

  static TtsEngineKind _kindOf(TtsServiceProvider provider) {
    final service = provider.service;
    if (service is! TtsService) {
      throw ArgumentError.value(
        service,
        'provider.service',
        'A TtsServiceProvider used as a synthesis engine must expose a '
            'TtsService',
      );
    }
    return ttsEngineKindForService(service);
  }
}
