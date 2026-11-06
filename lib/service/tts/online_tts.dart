import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/diagnostics/tts_diagnostics.dart';
import 'package:anx_reader/service/tts/engine/engine_kind_mapping.dart';
import 'package:anx_reader/service/tts/engine/flutter_tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/provider_tts_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:anx_reader/service/tts/models/tts_text_splitter.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_cursor.dart';
import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_speech_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_spoken_ranges.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/service/tts/pipeline/tts_utterance_splitter.dart';
import 'package:anx_reader/service/tts/rate_mapping.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';

/// Cloud-engine playback pipeline.
///
/// Responsibilities:
/// - decouple text segmentation (reader slices -> [TtsUtterance]s) from engine
///   consumption (one synthesis request per utterance),
/// - keep a stable cursor for every utterance and only advance the reader once
///   a slice is fully spoken (no skipped sentences when a sentence is split),
/// - guard every async continuation with a session id so stale engine/player
///   callbacks can never overwrite newer state,
/// - pause/resume the audio output in place, and migrate the cursor on engine
///   switch instead of restarting from the page top,
/// - apply rate changes through one entry point: server-side parameter when
///   the engine supports it, audio-player rate (applied after every source
///   load) when it does not.
class OnlineTts extends BaseTts {
  OnlineTts._({
    TtsSynthesisEngine Function()? engineResolver,
    TtsAudioOutput Function()? audioOutputFactory,
    bool? windowsOverride,
    Duration? synthesisTimeout,
    int? maxRetries,
    Duration Function(int failedAttempt)? rateLimitBackoff,
  })  : _engineResolver = engineResolver,
        _audioOutputFactory = audioOutputFactory,
        _windowsOverride = windowsOverride,
        _synthesisTimeout = synthesisTimeout ?? const Duration(seconds: 15),
        _maxRetries = maxRetries ?? 2,
        _rateLimitBackoff = rateLimitBackoff;

  static final OnlineTts _instance = OnlineTts._();

  factory OnlineTts() => _instance;

  /// Injectable instance for tests (fake engine + fake audio output).
  @visibleForTesting
  factory OnlineTts.withDependencies({
    required TtsSynthesisEngine Function() engineResolver,
    required TtsAudioOutput audioOutputFactory,
    bool windowsOverride = false,
    Duration synthesisTimeout = const Duration(seconds: 2),
    int maxRetries = 1,
    double initialRate = 0.6,
    TtsEngineKind? engineKindOverride,
    double volumeOverride = 0.8,
    double pitchOverride = 1.0,
    Duration? stallTimeout,
    Duration? advanceTimeout,
    int? pageTurnAnimationMs,
    Duration Function(int failedAttempt)? rateLimitBackoff,
  }) {
    final tts = OnlineTts._(
      engineResolver: engineResolver,
      audioOutputFactory: () => audioOutputFactory,
      windowsOverride: windowsOverride,
      synthesisTimeout: synthesisTimeout,
      maxRetries: maxRetries,
      rateLimitBackoff: rateLimitBackoff,
    );
    tts._rateOverride = initialRate;
    tts._engineKindOverride = engineKindOverride;
    tts._volumeOverride = volumeOverride;
    tts._pitchOverride = pitchOverride;
    if (stallTimeout != null) tts._stallTimeout = stallTimeout;
    if (advanceTimeout != null) tts._advanceTimeout = advanceTimeout;
    if (pageTurnAnimationMs != null) {
      tts._pageTurnAnimationMsOverride = pageTurnAnimationMs;
    }
    return tts;
  }

  final TtsSynthesisEngine Function()? _engineResolver;
  final TtsAudioOutput Function()? _audioOutputFactory;
  final bool? _windowsOverride;
  final Duration _synthesisTimeout;
  final int _maxRetries;

  /// Test-only override for the rate-limit retry schedule. Production uses
  /// [rateLimitRetryDelay] (600 ms / 1500 ms with ±100 ms jitter); injectable
  /// so pipeline tests can assert the retry *sequence* without real waits.
  final Duration Function(int failedAttempt)? _rateLimitBackoff;

  final math.Random _backoffRandom = math.Random();

  /// Maximum time to wait for an audio completion callback before declaring a
  /// stall and recovering (MiMo "hangs forever until manual pause/resume").
  Duration _stallTimeout = const Duration(seconds: 25);

  /// Maximum time to wait for the reader slice advance after a segment ended
  /// (webview roundtrip); a slow/failed advance must never freeze playback.
  Duration _advanceTimeout = const Duration(seconds: 8);

  int? _pageTurnAnimationMsOverride;

  /// Test hook: avoids touching shared preferences before they are loaded.
  double? _rateOverride;

  TtsEngineKind? _engineKindOverride;

  double? _volumeOverride;
  double? _pitchOverride;

  static const int _queueTarget = 8;

  /// How many utterances ahead the background synthesizer prefetches.
  ///
  /// Slow engines (StepAudio/MiMo) can take 1.5-5 s per request, which is
  /// longer than a short sentence's playback time; a deeper window keeps the
  /// synthesis pipeline filled so short segments do not starve the next one.
  static const int _prefetchAhead = 4;

  /// Maximum time to spend pre-synthesizing the first units of a cold session
  /// (engine switch) before letting playback start anyway.
  static const Duration _warmUpTimeout = Duration(seconds: 10);

  /// Audible-gap thresholds for the per-segment diagnostic.
  ///
  /// A chapter start cannot be prefetched (the foliate TTS iterator is bound
  /// to the section document, see docs/tts-round2/09-network-rate-limit.md), so
  /// one network round-trip legitimately lands on the audible critical path:
  /// Aliyun short-sentence synthesis is usually a few hundred ms, but network
  /// jitter can push a single round-trip into the 0.6-2.5 s band. Only a gap
  /// that clearly exceeds one round-trip is a defect worth a SEVERE log.
  @visibleForTesting
  static const int audibleGapInfoThresholdMs = 600;
  @visibleForTesting
  static const int audibleGapSevereThresholdMs = 2500;

  /// Exponential backoff used for rate-limited synthesis retries.
  ///
  /// The generic 120/240 ms retry loop is shorter than the gateway's own
  /// rate-limit window: the real-device log shows attempts 1/2/3 all rejected
  /// with `TOO_MANY_REQUESTS`, producing the 1.2-1.4 s gap. 600 ms then
  /// 1500 ms gives the gateway window time to clear while keeping the total
  /// retry budget bounded (the retry count itself does not change).
  @visibleForTesting
  static const List<Duration> rateLimitRetrySchedule = <Duration>[
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  /// ±[rateLimitRetryJitterMs] jitter so several pipelined clients do not
  /// retry in lockstep and re-create the burst.
  @visibleForTesting
  static const int rateLimitRetryJitterMs = 100;

  /// Delay before retry number [failedAttempt] (0-based) for a rate-limited
  /// failure, including jitter. Attempts beyond the schedule reuse the last
  /// entry (the retry count is bounded by `_maxRetries`).
  @visibleForTesting
  static Duration rateLimitRetryDelay(
    int failedAttempt, {
    math.Random? random,
  }) {
    final schedule = rateLimitRetrySchedule;
    final base = failedAttempt < schedule.length
        ? schedule[failedAttempt]
        : schedule.last;
    final span = 2 * rateLimitRetryJitterMs + 1;
    final jitter =
        (random ?? math.Random()).nextInt(span) - rateLimitRetryJitterMs;
    return base + Duration(milliseconds: jitter);
  }

  /// True when the audible gap must be logged as SEVERE (defect) instead of
  /// INFO (chapter-start network latency).
  @visibleForTesting
  static bool isSevereAudibleGap(int gapMs) =>
      gapMs > audibleGapSevereThresholdMs;

  Duration _retryDelayFor(int failedAttempt, {required bool rateLimited}) {
    if (!rateLimited) {
      return Duration(
          milliseconds: _genericRetryBackoffStepMs * (failedAttempt + 1));
    }
    final override = _rateLimitBackoff;
    if (override != null) return override(failedAttempt);
    return rateLimitRetryDelay(failedAttempt, random: _backoffRandom);
  }

  static const int _genericRetryBackoffStepMs = 120;

  /// Serializes every audio-output operation (prepare/start/discard/rate/stop).
  ///
  /// The production output pre-loads on an idle track (three tracks on desktop,
  /// two on mobile): the prefetch path and the playback path used to race on
  /// the same idle track (a concurrent `discardPrepared()` could stop/clear the
  /// payload between `prepare()` and `start()`, leaving playback started on a
  /// just-completed track whose MediaEngine ENDED event never fires — the
  /// observed 25 s stalls).
  Future<void> _audioOps = Future<void>.value();

  Future<T> _withAudioOps<T>(Future<T> Function() action) {
    final previous = _audioOps;
    final gate = Completer<void>();
    _audioOps = gate.future;
    Future<T> run() async {
      await previous;
      try {
        return await action();
      } finally {
        gate.complete();
      }
    }

    return run();
  }

  final TtsPlaybackStateMachine _machine = TtsPlaybackStateMachine();

  @override
  TtsPlaybackStateMachine get playbackMachine => _machine;

  TtsSynthesisEngine? _engine;
  TtsAudioOutput? _audio;
  TtsTextSource? _source;

  int _session = 0;
  bool _disposed = false;
  bool _paused = false;
  bool _runnerActive = false;
  Future<void>? _runner;
  Future<void>? _initFuture;
  Future<void>? _infraFuture;
  Completer<void>? _resumeGate;
  Completer<void>? _segmentCompleter;
  StreamSubscription<void>? _completionSub;

  final List<TtsUtterance> _queue = <TtsUtterance>[];
  final List<TtsTextSlice> _slices = <TtsTextSlice>[];
  final Set<String> _expandedSliceKeys = <String>{};
  int _peekWindow = 0;

  TtsUtterance? _currentUtterance;
  TtsResumeAnchor? _pendingAnchor;

  final Map<String, _PrefetchedAudio> _prefetched =
      <String, _PrefetchedAudio>{};

  /// Utterance whose audio was pre-loaded on the idle audio buffer.
  String? _preloadedUtteranceId;
  double? _preloadedRate;

  /// Slice advance runs *decoupled* from audio playback: it is requested as
  /// soon as a slice's last utterance ends, but the next audio segment starts
  /// immediately instead of waiting for the webview roundtrip (StepAudio
  /// perceptible stall between paragraphs).
  Future<void>? _advanceFuture;
  int _advanceGeneration = 0;

  /// Audio completion / advance watchdog state (stall recovery).
  Timer? _stallTimer;
  TtsStallStage? _stallStage;
  DateTime? _stallStartedAt;
  String? _stallUtteranceId;
  DateTime? _segmentStartedAt;
  DateTime? _lastSegmentEndedAt;

  String? _replayTextOverride;
  bool _replayCurrent = false;

  /// Number of utterances the next session start should synthesize before the
  /// first segment becomes audible (engine-switch cold start warm-up).
  int _warmUpUnits = 0;

  String? _lastReadCfi;
  String? _lastPageToken;

  /// Number of utterance-sized units that could not be spoken because the
  /// engine returned an empty result for non-empty text. Surfaced by the UI.
  final ValueNotifier<int> skippedSegmentsNotifier = ValueNotifier<int>(0);

  /// Last-read sentence position, consumed by the resume logic.
  final ValueNotifier<TtsReadingPositionState?> readingPositionNotifier =
      ValueNotifier<TtsReadingPositionState?>(null);

  // ============ Identity / capabilities ============

  @override
  TtsEngineKind get engineKind =>
      _engineKindOverride ?? currentTtsEngineKind(Prefs().ttsService);

  @override
  String get engineId => Prefs().ttsService;

  TtsSynthesisEngine get _activeEngine {
    final resolver = _engineResolver;
    if (resolver != null) {
      return _engine ??= resolver();
    }
    final current = _engine;
    if (current != null && current.kind == engineKind) return current;
    final resolved =
        ProviderTtsSynthesisEngine(getTtsService(Prefs().ttsService).provider);
    _engine = resolved;
    return resolved;
  }

  @override
  TtsEngineCapabilities get capabilities => _activeEngine.capabilities;

  // ============ Settings ============

  @override
  double get volume => _volumeOverride ?? Prefs().ttsVolume;

  @override
  set volume(double value) {
    if (_volumeOverride != null) {
      _volumeOverride = value;
    } else {
      Prefs().ttsVolume = value;
    }
    final audio = _audio;
    if (audio != null) {
      unawaited(audio.setVolume(value));
    }
  }

  @override
  double get pitch => _pitchOverride ?? Prefs().ttsPitch;

  @override
  set pitch(double value) {
    if (_pitchOverride != null) {
      _pitchOverride = value;
    } else {
      Prefs().ttsPitch = value;
    }
  }

  @override
  double get rate => _rateOverride ?? Prefs().ttsRate;

  @Deprecated('Use changeRate(double) so rate changes are applied atomically')
  set rate(double value) {
    unawaited(changeRate(value));
  }

  @override
  Future<void> changeRate(double value) async {
    final normalized = clampTtsRate(value);
    final multiplier = ttsRateToMultiplier(normalized);
    if (_rateOverride != null) {
      _rateOverride = normalized;
    } else {
      Prefs().ttsRate = normalized;
    }
    _publish(TtsRateChangeRequested(sessionId: _session, rate: normalized));
    recordEvent(
        TtsRateChanged(rate: normalized, effectiveMultiplier: multiplier));

    final caps = capabilities;
    if (caps.appliesRateOnServer) {
      // Server-side rate: drop buffered/prepared audio so following utterances
      // are re-synthesized with the new parameter. The current sentence keeps
      // playing; nothing is stopped or cleared on the audio output.
      _prefetched.clear();
      await _withAudioOps(() async {
        _preloadedUtteranceId = null;
        _preloadedRate = null;
        final audio = _audio;
        if (audio == null) return;
        try {
          await audio.discardPrepared();
        } catch (e) {
          AnxLog.info('TTS rate change prepare discard failed: $e');
        }
      });
      return;
    }

    // Player-side rate (MiMo): apply immediately so the current sentence is
    // affected too; every later utterance re-applies it after loading its
    // source (a new media source resets the player rate). Already-synthesized
    // prefetched payloads stay valid: the rate is a player property, not part
    // of the audio data (re-synthesizing them caused seconds-long gaps).
    try {
      await _withAudioOps(() async {
        final audio = _audio;
        if (audio == null) return;
        await audio.setPlaybackRate(multiplier);
      });
    } catch (e) {
      final error = TtsRateChangeError(
        engine: engineKind,
        message: 'Failed to apply playback rate',
        cause: e,
        context: {'rate': normalized.toString(), 'multiplier': '$multiplier'},
      );
      recordEvent(TtsPlaybackFailure(error: error));
    }
  }

  // ============ Lifecycle ============

  @override
  TtsTextSource? get textSource => _source;

  @override
  Future<void> init({
    required TtsTextSource textSource,
    TtsResumeAnchor? anchor,
  }) async {
    // Bind the source synchronously so a play() that races this async init
    // never observes a half-initialized engine.
    _source = textSource;
    _pendingAnchor = anchor;
    final future = _initialize(anchor);
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  Future<void> _initialize(TtsResumeAnchor? anchor) async {
    await stop();
    _pendingAnchor = anchor;
    await _beginSession(anchor: anchor, locate: false);
  }

  Future<void> _beginSession({
    TtsResumeAnchor? anchor,
    bool locate = true,
  }) async {
    final session = ++_session;
    _pendingAnchor = anchor;
    _paused = false;
    _publish(TtsSessionStarted(
      sessionId: session,
      engine: engineKind,
      rate: rate,
      anchor: anchor,
    ));
    try {
      await _ensureInfrastructure();
      if (!_isActive(session)) return;
      _publish(TtsEngineReady(sessionId: session));
      if (!locate) return;
      _startRunner(session);
    } catch (e) {
      _publishFailure(session, _toError(e, TtsStage.initialize));
    }
  }

  Future<void> _ensureInfrastructure() {
    if (_engineResolver != null) {
      _engine = _engineResolver();
    } else if (_engine == null || _engine!.kind != engineKind) {
      _engine = ProviderTtsSynthesisEngine(
          getTtsService(Prefs().ttsService).provider);
    }
    final existing = _infraFuture;
    if (existing != null) return existing;
    final future = _initializeAudioOutput();
    _infraFuture = future;
    return future;
  }

  Future<void> _initializeAudioOutput() async {
    final audio = _createAudioOutput();
    _audio = audio;
    await audio.initialize(warmUp: _shouldWarmUp());
    await audio.setVolume(volume);
    if (!capabilities.appliesRateOnServer) {
      await audio.setPlaybackRate(ttsRateToMultiplier(rate));
    }
    await _completionSub?.cancel();
    _completionSub = audio.completions.listen((_) {
      _onAudioCompleted();
    });
  }

  TtsAudioOutput _createAudioOutput() {
    final factory = _audioOutputFactory;
    if (factory != null) return factory();
    return FlutterTtsAudioOutput();
  }

  bool _shouldWarmUp() {
    final override = _windowsOverride;
    if (override != null) return override;
    return AnxPlatform.isWindows;
  }

  Future<void> _startRunner(int session, {bool locate = true}) async {
    _publish(TtsTextLocating(sessionId: session));
    _runnerActive = true;
    final runner = _runSession(session, locate: locate);
    _runner = runner;
    unawaited(runner);
  }

  /// Test hook: completes when the current playback session loop ends.
  @visibleForTesting
  Future<void> get currentSession => _runner ?? Future<void>.value();

  Future<void> _runSession(int session, {bool locate = true}) async {
    try {
      if (locate) {
        final anchor = _pendingAnchor;
        _pendingAnchor = null;
        final source = _source;
        if (source == null) {
          _publishFailure(
            session,
            TtsInitializationError(
                engine: engineKind, message: 'No text source bound'),
          );
          return;
        }
        final located = await source.locate(resumeAtCfi: anchor?.cfi);
        if (!_isActive(session)) return;
        if (located == null || located.isBlank) {
          _publishEmpty(session);
          return;
        }
        _seedLocatedSlice(located, anchor);
        await _refreshPageToken();
        if (!_isActive(session)) return;
      }
      await _playLoop(session);
    } catch (e) {
      if (_isActive(session)) {
        _publishFailure(session, _toError(e, TtsStage.play));
      }
    } finally {
      _runnerActive = false;
    }
  }

  void _seedLocatedSlice(TtsTextSlice located, TtsResumeAnchor? anchor) {
    _queue.clear();
    _slices.clear();
    _expandedSliceKeys.clear();
    _sliceLastUtteranceIds.clear();
    _peekWindow = 0;
    _currentUtterance = null;
    _prefetched.clear();
    _preloadedUtteranceId = null;
    _preloadedRate = null;
    _replayCurrent = false;
    _replayTextOverride = null;
    _advanceFuture = null;
    _advanceGeneration++;
    _lastSegmentEndedAt = null;
    _currentSegmentGapMs = 0;
    _cancelStallWatchdog();

    var text = located.text;
    if (anchor != null && anchor.charOffset > 0) {
      final offset = calibrateTtsResumeOffset(text, anchor.charOffset);
      if (offset > 0 && offset < text.length) {
        text = text.substring(offset);
        recordEvent(TtsBoundaryGuarded(
          utteranceId: anchor.utteranceId ?? located.key,
          reason: 'engine-switch-anchor@$offset',
        ));
      }
    }
    _slices.add(TtsTextSlice(
      text: text,
      cfi: located.cfi,
      pageToken: located.pageToken,
      index: 0,
    ));
    _lastReadCfi = located.cfi ?? _lastReadCfi;
    _updateReadingPosition();
    if (located.cfi != null && located.cfi!.isNotEmpty) {
      recordEvent(TtsSentenceStarted(cfi: located.cfi!, at: DateTime.now()));
    }
  }

  Future<void> _playLoop(int session) async {
    while (_isActive(session)) {
      if (_paused) {
        await _waitWhilePaused(session);
        if (!_isActive(session)) return;
      }
      await _fillQueue(session);
      if (!_isActive(session)) return;
      if (playbackState.hasError) return;
      if (_queue.isEmpty) {
        // Never stop silently while an advance is still in flight; wait for it
        // (bounded) and let _fillQueue pull the next slice instead of ending
        // the session during a slow webview roundtrip.
        final advance = _advanceFuture;
        if (advance != null) {
          await advance;
          if (!_isActive(session)) return;
          if (playbackState.hasError) return;
          continue;
        }
        _publish(TtsQueueExhausted(sessionId: session));
        recordEvent(TtsStopped(reason: 'queue-exhausted'));
        await _source?.clearHighlight();
        return;
      }

      var utterance = _queue.removeAt(0);
      _currentUtterance = utterance;
      if (utterance.text.trim().isEmpty) {
        _onSilentUtterance(session);
        continue;
      }
      final speechPreview = prepareTtsSpeechText(utterance.text);
      if (speechPreview.speechText.trim().isEmpty) {
        // Unit consisting only of sentence-final annotations ([12]): keep the
        // display/range bookkeeping but do not synthesize, wait or count it as
        // a skipped segment.
        recordEvent(TtsBoundaryGuarded(
          utteranceId: utterance.id,
          reason: 'annotation-only-unit',
        ));
        _publish(TtsUtteranceCompleted(sessionId: session));
        _handleUtteranceBoundary(session, utterance);
        continue;
      }

      if (utterance.isFirstUnitOfSlice) {
        // Just-in-time page-break detection: the reader TTS cursor must be on
        // this slice for the bridge to answer, which is only true after the
        // previous slice advance completed. Bounded wait so a slow webview can
        // never stall playback; when it is too slow we fall back to a page
        // turn at the sentence end.
        await _awaitPendingAdvanceBriefly();
        if (!_isActive(session)) return;
        utterance = await _applyPageBreakBeforeSlice(session, utterance);
        if (!_isActive(session)) return;
        if (utterance.text.trim().isEmpty) continue;
        // The page-break split may replace the unit with its `.a` remainder;
        // keep the "current utterance" bookkeeping in sync so pause cursors,
        // resume anchors and diagnostics never point at the pre-split unit.
        _currentUtterance = utterance;
      }

      final startCursor = TtsPlaybackCursor.startOf(utterance);
      _publish(TtsUtteranceBuffering(
        sessionId: session,
        utterance: utterance,
        cursor: startCursor,
      ));

      // Cold-start warm-up (engine switch): synthesize the first units before
      // the first segment becomes audible. Slow cloud engines (StepAudio/MiMo)
      // need longer per sentence than a short sentence takes to play, so a
      // single-segment cold start is followed by a multi-second silence (field
      // log: 4859 ms after a MiMo→StepAudio switch). Runs only once per session
      // and keeps playback state "buffering" while it works.
      final pendingWarmUp = _warmUpUnits;
      if (pendingWarmUp > 0) {
        _warmUpUnits = 0;
        await _warmUpQueue(session, utterance, pendingWarmUp);
        if (!_isActive(session)) return;
      } else {
        // Kick prefetch *before* the playback path blocks on the current
        // segment. Requests issued only after the segment starts put their
        // full synthesis latency on the audible critical path; starting them
        // here overlaps that latency with the current segment's acquisition
        // and playback. Runs after the page-break split so an utterance that
        // is about to be re-split is not synthesized twice.
        _prefetchBeforeAcquire(session, utterance);
      }

      final bytes = await _acquireAudioSafely(session, utterance);
      if (!_isActive(session)) return;
      if (bytes == null) {
        // Either the utterance was split into smaller requests (already
        // requeued) or a failure was published; both are handled upstream.
        if (playbackState.hasError) return;
        continue;
      }
      if (bytes.isEmpty) {
        _onSilentUtterance(session);
        continue;
      }

      await _waitWhilePaused(session);
      if (!_isActive(session)) return;

      if (_replayCurrent) {
        _replayCurrent = false;
        final override = _replayTextOverride;
        _replayTextOverride = null;
        if (override != null && override.trim().isNotEmpty) {
          final remaining = await _synthesizeBytes(
            session,
            utterance,
            textOverride: override,
          );
          if (!_isActive(session)) return;
          if (remaining == null || remaining.isEmpty) {
            _queue.insert(0, utterance);
            continue;
          }
          await _prepareAndStart(
            session,
            utterance,
            remaining,
            cursor: _pausedCursorFor(utterance),
          );
        } else {
          await _prepareAndStart(session, utterance, bytes,
              cursor: startCursor);
        }
      } else {
        await _prepareAndStart(session, utterance, bytes, cursor: startCursor);
      }
      if (!_isActive(session)) return;
      if (_paused) {
        // Pause arrived while starting: keep the segment paused and wait.
        await _waitWhilePaused(session);
        if (!_isActive(session)) return;
      }

      _prebufferNext(session);
      await _segmentCompleter?.future;
      _segmentCompleter = null;
      if (!_isActive(session)) return;
      if (_paused) {
        await _waitWhilePaused(session);
        if (!_isActive(session)) return;
      }

      _publish(TtsUtteranceCompleted(sessionId: session));
      // Decoupled from audio: scheduling the reader advance / page turn here
      // must not block the next segment (StepAudio's audible gap).
      _handleUtteranceBoundary(session, utterance);
    }
  }

  /// Acquire audio for [utterance], reporting synthesis failures as a typed
  /// error instead of skipping the segment silently.
  Future<Uint8List?> _acquireAudioSafely(
    int session,
    TtsUtterance utterance,
  ) async {
    try {
      return await _acquireAudio(session, utterance);
    } on TtsPlaybackError catch (e) {
      _queue.insert(0, utterance);
      _publishFailure(session, e);
      return null;
    }
  }

  Future<Uint8List?> _acquireAudio(
    int session,
    TtsUtterance utterance,
  ) async {
    final entry = _prefetched.remove(utterance.id);
    // Player-rate engines (MiMo) apply the rate on the audio player, so the
    // already-synthesized bytes stay valid across a rate change. Re-synthesizing
    // them after every slider move caused multi-second audible gaps.
    final rateMatches = entry != null &&
        (!capabilities.appliesRateOnServer || entry.rate == rate);
    if (rateMatches) {
      return entry.bytes;
    }
    return _synthesizeBytes(session, utterance);
  }

  Future<Uint8List?> _synthesizeBytes(
    int session,
    TtsUtterance utterance, {
    String? textOverride,
  }) {
    // Single-flight per (utterance, text-override): the pre-buffer and the main
    // playback loop may request the same utterance at the same time. Sharing
    // one future prevents duplicate synthesis requests (duplicated audio)
    // and duplicated oversized splits.
    final key = textOverride == null
        ? utterance.id
        : '${utterance.id}#override:${textOverride.hashCode}';
    final inFlight = _synthInFlight[key];
    if (inFlight != null) return inFlight;
    final future = _synthesizeBytesOnce(
      session,
      utterance,
      textOverride: textOverride,
    );
    _synthInFlight[key] = future;
    // Clean up the single-flight entry when the request settles. The derived
    // future must be handled here, otherwise a synthesis failure would surface
    // as an unhandled async error to every shared caller.
    future.then<void>(
      (_) {
        if (identical(_synthInFlight[key], future)) _synthInFlight.remove(key);
      },
      onError: (Object _) {
        if (identical(_synthInFlight[key], future)) _synthInFlight.remove(key);
      },
    );
    return future;
  }

  final Map<String, Future<Uint8List?>> _synthInFlight =
      <String, Future<Uint8List?>>{};

  Future<Uint8List?> _synthesizeBytesOnce(
    int session,
    TtsUtterance utterance, {
    String? textOverride,
  }) async {
    final rawText = textOverride ?? utterance.text;
    // Sentence-final numeric annotations ([12]) are display-only: never send
    // them to the engine. The utterance model keeps the raw text/ranges for
    // highlighting and location.
    final prepared = prepareTtsSpeechText(rawText);
    final text = prepared.speechText;
    if (text.trim().isEmpty) {
      // Annotation-only unit: nothing to speak. The playback loop skips it
      // without treating it as a skipped segment or extra wait.
      return Uint8List(0);
    }
    final engine = _activeEngine;
    final config = TtsSpeechConfig(
      rate: rate,
      pitch: pitch,
      volume: volume,
    );
    Object? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (!_isActive(session)) return null;
      final requestedAt = DateTime.now();
      diagnostics.add(TtsSynthesisRequested(
        at: requestedAt,
        engine: engineKind,
        utteranceId: utterance.id,
        chars: text.length,
        rate: rate,
        attempt: attempt + 1,
      ));
      try {
        final bytes = await engine
            .synthesize(TtsSynthesisRequest(
              text: text,
              config: config,
              engine: engineKind,
              utteranceId: utterance.id,
            ))
            .timeout(_synthesisTimeout);
        if (bytes.isEmpty && text.trim().isNotEmpty) {
          throw TtsEngineSynthesisException(
            engine: engineKind,
            message: 'Engine returned empty audio for non-empty text',
            context: {'chars': '${text.length}'},
          );
        }
        diagnostics.add(TtsSynthesisReceived(
          at: DateTime.now(),
          engine: engineKind,
          utteranceId: utterance.id,
          elapsedMs: DateTime.now().difference(requestedAt).inMilliseconds,
          bytes: bytes.length,
        ));
        return bytes;
      } on TtsEngineSynthesisException catch (e) {
        lastError = e;
        final rateLimited = e.isRateLimited;
        diagnostics.add(TtsSynthesisFailed(
          at: DateTime.now(),
          engine: engineKind,
          utteranceId: utterance.id,
          elapsedMs: DateTime.now().difference(requestedAt).inMilliseconds,
          // Mark the rate-limit class inside the existing diagnostic field so
          // device logs make the gateway rejection distinguishable from a
          // content error without extending the shared event schema.
          error: rateLimited ? 'rate-limited: ${e.message}' : e.message,
          attempt: attempt + 1,
        ));
        if (e.isOversized && rawText.length > 1) {
          // Split the RAW text so the requeued units keep the display ranges
          // (annotations included); each unit is sanitized again on request.
          _splitAndRequeue(session, utterance, rawText);
          return null;
        }
        if (attempt >= _maxRetries) break;
        if (rateLimited) {
          final delay = _retryDelayFor(attempt, rateLimited: true);
          AnxLog.info('TTS[diag] synthesis rate-limited attempt=${attempt + 1}/'
              '${_maxRetries + 1} backoffMs=${delay.inMilliseconds} '
              'utterance=${utterance.id} engine=${engineKind.name}');
          await Future<void>.delayed(delay);
          continue;
        }
      } catch (e) {
        lastError = e;
        diagnostics.add(TtsSynthesisFailed(
          at: DateTime.now(),
          engine: engineKind,
          utteranceId: utterance.id,
          elapsedMs: DateTime.now().difference(requestedAt).inMilliseconds,
          error: '$e',
          attempt: attempt + 1,
        ));
        if (attempt >= _maxRetries) break;
      }
      // Non-rate-limit failures keep the original short retry loop.
      await Future<void>.delayed(_retryDelayFor(attempt, rateLimited: false));
    }
    throw TtsSynthesisError(
      engine: engineKind,
      message: 'Synthesis failed after ${_maxRetries + 1} attempts',
      cause: lastError,
      context: {
        'utterance': utterance.id,
        'chars': '${text.length}',
        'rate': '$rate',
      },
    );
  }

  /// Split an over-limit request into two halves and put them back in front of
  /// the queue. This is the graceful fallback for engines whose documented
  /// limit is smaller than expected (the Aliyun paragraph-skip class of bugs):
  /// text is split instead of silently dropped.
  void _splitAndRequeue(
    int session,
    TtsUtterance utterance,
    String text,
  ) {
    final chunks = splitTtsText(text, math.max(1, text.length ~/ 2));
    if (chunks.length <= 1) return;
    final units = <TtsUtterance>[];
    var offset = 0;
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      units.add(TtsUtterance(
        id: '${utterance.id}~$i',
        paragraphId: utterance.paragraphId,
        unitIndex: utterance.unitIndex,
        text: chunk,
        range: TtsCharRange(
          start: utterance.range.start + offset,
          end: utterance.range.start + offset + chunk.length,
        ),
        boundaryBefore:
            i == 0 ? utterance.boundaryBefore : TtsBoundaryBefore.hardCut,
        cfi: utterance.cfi,
        isParagraphStart: i == 0 && utterance.isParagraphStart,
        sliceIndex: utterance.sliceIndex,
      ));
      offset += chunk.length;
    }
    recordEvent(TtsBoundaryGuarded(
      utteranceId: utterance.id,
      reason: 'engine-oversized-split-${chunks.length}',
    ));
    _queue.insertAll(0, units);
    for (final entry in _sliceLastUtteranceIds.entries) {
      if (entry.value == utterance.id) {
        _sliceLastUtteranceIds[entry.key] = units.last.id;
      }
    }
  }

  Future<void> _prepareAndStart(
    int session,
    TtsUtterance utterance,
    Uint8List bytes, {
    required TtsPlaybackCursor cursor,
  }) async {
    final audio = _audio;
    if (audio == null) {
      throw StateError('Audio output is not initialized');
    }
    final mime = _mimeType();
    _segmentSession = session;
    _segmentCompleter = Completer<void>();
    _segmentStartedAt = DateTime.now();
    _publish(TtsUtteranceStarted(
      sessionId: session,
      utterance: utterance,
      cursor: cursor,
    ));
    _lastReadCfi = utterance.cfi ?? _lastReadCfi;
    _updateReadingPosition();
    recordEvent(TtsSentenceStarted(
      cfi: utterance.cfi ?? '',
      at: DateTime.now(),
    ));

    // Text/iterator may run seconds ahead of the audio (silent prefetch
    // advance). Paint the selection only now, right before the segment becomes
    // audible, so the highlighted text always matches the spoken progress. This
    // runs for *every* utterance: a sentence split by the page boundary (`.a`
    // / `.b`) or by engine request limits repaints the exact spoken sub-span,
    // drops the previous one, and forces the reader back to the sentence page
    // when the user manually paged away.
    await _highlightSpokenBounded(utterance);
    if (!_isActive(session)) return;

    try {
      await _withAudioOps(() async {
        final alreadyPrepared = _isUtterancePrepared(utterance, audio);
        try {
          if (!alreadyPrepared) {
            // No `discardPrepared()` here on purpose: `prepare()` replaces the
            // idle track's media source itself, while the explicit discard
            // stopped a track that could still be flushing its sentence tail
            // (the reported tail-character loss) or that had just delivered
            // ENDED (the 25 s stall window). A discarded payload stays
            // unreachable because `start()` only plays an explicitly prepared
            // payload.
            await audio.prepare(TtsAudioRequest(
              bytes: bytes,
              mimeType: mime,
              utteranceId: utterance.id,
            ));
          }
        } finally {
          _preloadedUtteranceId = null;
          _preloadedRate = null;
        }
        await audio.start(
          playbackRate: ttsRateToMultiplier(rate),
          applyRate: !capabilities.appliesRateOnServer,
        );
      });
    } catch (e) {
      _cancelStallWatchdog();
      _segmentCompleter?.complete();
      final error = TtsAudioOutputError(
        engine: engineKind,
        message: 'Audio output failed to start',
        cause: e,
        context: {'utterance': utterance.id},
      );
      recordEvent(TtsPlaybackFailure(error: error));
      _publishFailure(session, error);
      return;
    }
    if (!_isActive(session)) return;
    _currentSegmentGapMs = _lastSegmentEndedAt == null
        ? 0
        : _segmentStartedAt!.difference(_lastSegmentEndedAt!).inMilliseconds;
    diagnostics.add(TtsAudioSegmentStarted(
      at: _segmentStartedAt!,
      engine: engineKind,
      utteranceId: utterance.id,
      queueDepth: _queue.length,
      rate: rate,
      gapMs: _currentSegmentGapMs,
    ));
    if (_currentSegmentGapMs > audibleGapInfoThresholdMs) {
      final message = 'TTS[diag] audible gap ${_currentSegmentGapMs}ms before '
          '${utterance.id}';
      // A chapter start cannot be prefetched (the foliate TTS iterator is
      // per-section, see docs/tts-round2/09-network-rate-limit.md), so one
      // network round-trip legitimately lands on the audible path. Only a
      // multiple-round-trip gap is a defect worth SEVERE; the rest stays INFO
      // so a normal chapter transition no longer looks like a crash.
      if (isSevereAudibleGap(_currentSegmentGapMs)) {
        AnxLog.severe(message);
      } else {
        AnxLog.info(message);
      }
    }
    _armStallWatchdog(
      session: session,
      stage: TtsStallStage.audioCompletion,
      utteranceId: utterance.id,
      timeout: _stallTimeout,
    );
  }

  /// Whether the audio output already holds the payload for [utterance].
  ///
  /// Player-rate engines apply the rate on the player, so their prepared bytes
  /// remain valid after a rate change; server-rate engines need a re-synthesis.
  bool _isUtterancePrepared(TtsUtterance utterance, TtsAudioOutput audio) {
    if (_preloadedUtteranceId != utterance.id || !audio.hasPrepared) {
      return false;
    }
    if (!capabilities.appliesRateOnServer) return true;
    return _preloadedRate == rate;
  }

  /// Repaints the reader highlight for exactly the spoken part of [utterance].
  ///
  /// Bounded so a busy/slow webview can never stall the audio start; the source
  /// also force-scrolls back to the spoken sentence when the user manually paged
  /// away and returns whether it could show the page.
  Future<void> _highlightSpokenBounded(TtsUtterance utterance) async {
    final source = _source;
    if (source is! TtsHighlightCapable) return;
    final ranges = spokenRangesFor(utterance);
    final watch = Stopwatch()..start();
    var ok = false;
    try {
      ok = await (source as TtsHighlightCapable)
          .highlightSpoken(cfi: utterance.cfi, ranges: ranges)
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      ok = false;
      AnxLog.info('TTS highlight sync failed: $e');
    }
    watch.stop();
    diagnostics.add(TtsHighlightSynced(
      at: DateTime.now(),
      engine: engineKind,
      utteranceId: utterance.id,
      elapsedMs: watch.elapsedMilliseconds,
      ok: ok,
    ));
  }

  /// Pre-synthesizes the current utterance and the following units of a cold
  /// session (engine switch) so playback starts with a lead instead of running
  /// dry after the first sentence.
  ///
  /// Called *after* the page-break split of the current utterance, so the queue
  /// already holds the final units. Best effort and bounded: a slow or failing
  /// engine must never block the switch forever; when the bound is hit playback
  /// starts and the normal pipeline (with its typed errors) takes over.
  Future<void> _warmUpQueue(
    int session,
    TtsUtterance current,
    int units,
  ) async {
    if (!_isActive(session)) return;
    final targets = <TtsUtterance>[
      current,
      ..._queue.take(math.max(0, units - 1)),
    ].where((utterance) => utterance.text.trim().isNotEmpty).toList();
    if (targets.isEmpty) return;
    final watch = Stopwatch()..start();
    final futures = <Future<void>>[
      for (final utterance in targets) _prebuffer(session, utterance),
    ];
    try {
      await Future.wait(futures).timeout(_warmUpTimeout);
    } on TimeoutException catch (e) {
      AnxLog.info('TTS warm-up timed out after ${_warmUpTimeout.inSeconds}s: '
          '$e');
    } catch (e) {
      AnxLog.info('TTS warm-up failed: $e');
    }
    if (!_isActive(session)) return;
    final ready = targets
        .where((utterance) => _prefetched.containsKey(utterance.id))
        .length;
    AnxLog.info('TTS[diag] engine.warmup units=$ready/${targets.length} '
        'elapsedMs=${watch.elapsedMilliseconds}');
    if (ready > 0) _maybePreloadNext(session, current);
    // Continue filling the prefetch window in the background.
    _prebufferNext(session);
  }

  /// Starts synthesis of the current utterance first (so it wins the request
  /// order and the network), then prefetches the following window.
  void _prefetchBeforeAcquire(int session, TtsUtterance current) {
    if (current.text.trim().isNotEmpty &&
        !_prefetched.containsKey(current.id)) {
      unawaited(_prebuffer(session, current));
    }
    _prebufferNext(session);
  }

  void _prebufferNext(int session) {
    if (_queue.isEmpty) return;
    // Prefetch a small lookahead window; single-flight synthesis dedupes when
    // the playback loop requests the same utterance.
    final candidates = _queue.take(_prefetchAhead).toList(growable: false);
    for (final candidate in candidates) {
      if (candidate.text.trim().isEmpty) continue;
      if (_prefetched.containsKey(candidate.id)) continue;
      unawaited(_prebuffer(session, candidate));
    }
    // Pre-load only the immediate next utterance on the audio output.
    final next = candidates.isEmpty ? null : candidates.first;
    if (next == null) return;
    if (_preloadedUtteranceId != next.id) {
      _maybePreloadNext(session, next);
    }
  }

  void _maybePreloadNext(int session, TtsUtterance candidate) {
    final entry = _prefetched[candidate.id];
    if (entry == null) return;
    // Server-rate engines need bytes synthesized at the current rate; for
    // player-rate engines (MiMo) the rate is applied on the player, so the
    // already-synthesized payload is reusable across rate changes.
    if (capabilities.appliesRateOnServer && entry.rate != rate) return;
    final audio = _audio;
    if (audio == null || !audio.supportsPreload) return;
    final alreadyPrepared = _preloadedUtteranceId == candidate.id &&
        (!capabilities.appliesRateOnServer || _preloadedRate == rate);
    if (alreadyPrepared) return;
    unawaited(_preloadOnIdleBuffer(session, candidate, entry));
  }

  Future<void> _preloadOnIdleBuffer(
    int session,
    TtsUtterance candidate,
    _PrefetchedAudio entry,
  ) async {
    try {
      await _withAudioOps(() async {
        final audio = _audio;
        if (audio == null || !_isActive(session)) return;
        if (capabilities.appliesRateOnServer && entry.rate != rate) return;
        // Overwrite the idle track's source directly instead of stopping it
        // first: the track may be the one that just finished, and a stop()
        // there clips the still-draining sentence tail (see `_prepareAndStart`).
        await audio.prepare(TtsAudioRequest(
          bytes: entry.bytes,
          mimeType: _mimeType(),
          utteranceId: candidate.id,
        ));
        if (!_isActive(session)) return;
        _preloadedUtteranceId = candidate.id;
        _preloadedRate = entry.rate;
      });
    } catch (e) {
      AnxLog.info('TTS preload failed for ${candidate.id}: $e');
    }
  }

  Future<void> _prebuffer(int session, TtsUtterance candidate) async {
    try {
      final rateAtRequest = rate;
      final bytes = await _synthesizeBytes(session, candidate);
      if (!_isActive(session) || bytes == null || bytes.isEmpty) return;
      if (rate != rateAtRequest) return;
      if (_prefetched.length >= _prefetchAhead * 2) {
        _prefetched.remove(_prefetched.keys.first);
      }
      _prefetched[candidate.id] =
          _PrefetchedAudio(bytes: bytes, rate: rateAtRequest);
      _maybePreloadNext(session, candidate);
    } catch (_) {
      // Prefetch is best-effort; the main loop reports real failures.
    }
  }

  void _onAudioCompleted() {
    if (_disposed) return;
    if (_segmentSession != _session) return;
    // A completion that arrives after the segment was already settled (late
    // callback from a retired track, duplicate ENDED event) must not advance
    // playback or overwrite the gap bookkeeping.
    final completer = _segmentCompleter;
    if (completer == null || completer.isCompleted) return;
    _cancelStallWatchdog();
    final now = DateTime.now();
    final startedAt = _segmentStartedAt;
    final utteranceId = _currentUtterance?.id ?? '';
    if (startedAt != null) {
      diagnostics.add(TtsAudioSegmentCompleted(
        at: now,
        engine: engineKind,
        utteranceId: utteranceId,
        elapsedMs: now.difference(startedAt).inMilliseconds,
        interSegmentGapMs: _currentSegmentGapMs,
      ));
    }
    _lastSegmentEndedAt = now;
    if (_paused) return;
    completer.complete();
  }

  /// Decides what has to happen when one audio segment finished.
  ///
  /// Runs synchronously in the audio loop and only *schedules* the reader
  /// advance / page turn: the next segment starts immediately, so a slow
  /// webview roundtrip can no longer create StepAudio's inter-paragraph stall
  /// or MiMo's "stopped after selecting the next line".
  void _handleUtteranceBoundary(int session, TtsUtterance utterance) {
    final endedAt = _lastSegmentEndedAt ?? DateTime.now();
    final scheduledTurn = _pageBreakTurns[utterance.id];
    if (scheduledTurn != null && _turnedBreaks.add(utterance.id)) {
      // The split entry has been consumed; keeping it would only leak memory
      // for the rest of the session.
      _pageBreakTurns.remove(utterance.id);
      unawaited(
          _performPageBreakTurn(session, utterance.id, scheduledTurn, endedAt));
      return;
    }
    final lastOfSlice = _lastUtteranceIdOfSlice(utterance);
    if (lastOfSlice != null && lastOfSlice == utterance.id) {
      _startAdvanceSlice(session, endedAt);
    }
  }

  /// Page turn for a page boundary that falls *inside* a sentence: the page is
  /// turned right after the page-last-character segment finishes, while the
  /// remainder of the sentence keeps playing.
  Future<void> _performPageBreakTurn(
    int session,
    String utteranceId,
    Future<void> Function() turn,
    DateTime audioEndedAt,
  ) async {
    final requestedAt = DateTime.now();
    diagnostics.add(TtsPageTurnRequested(
      at: requestedAt,
      engine: engineKind,
      source: TtsPageTurnSource.pageBreak,
      fromCfi: _lastReadCfi ?? '',
    ));
    try {
      await turn().timeout(_advanceTimeout);
      final completedAt = DateTime.now();
      final elapsedMs = completedAt.difference(audioEndedAt).inMilliseconds;
      diagnostics.add(TtsPageTurnCompleted(
        at: completedAt,
        engine: engineKind,
        source: TtsPageTurnSource.pageBreak,
        elapsedMs: elapsedMs,
        animationMs: _pageTurnAnimationMs(),
      ));
      recordEvent(TtsPageTurned(
        fromCfi: _lastReadCfi ?? '',
        at: completedAt,
      ));
      unawaited(_refreshPageToken());
    } catch (e) {
      recordEvent(TtsBoundaryGuarded(
        utteranceId: utteranceId,
        reason: 'page-break-turn-failed',
      ));
      AnxLog.info('TTS page-break turn failed: $e');
    }
    if (!_isActive(session)) return;
  }

  void _startAdvanceSlice(int session, DateTime audioEndedAt) {
    if (_advanceFuture != null) return;
    final generation = ++_advanceGeneration;
    final future = _runAdvanceSlice(session, generation, audioEndedAt);
    _advanceFuture = future;
    unawaited(future.then<void>((_) {
      if (identical(_advanceFuture, future)) _advanceFuture = null;
    }, onError: (Object _) {
      if (identical(_advanceFuture, future)) _advanceFuture = null;
    }));
  }

  Future<void> _runAdvanceSlice(
    int session,
    int generation,
    DateTime audioEndedAt,
  ) async {
    final source = _source;
    if (source == null) return;
    final requestedAt = DateTime.now();
    diagnostics.add(TtsSliceAdvanceRequested(
      at: requestedAt,
      engine: engineKind,
      fromCfi: _lastReadCfi ?? '',
    ));
    diagnostics.add(TtsPageTurnRequested(
      at: requestedAt,
      engine: engineKind,
      source: TtsPageTurnSource.sliceEnd,
      fromCfi: _lastReadCfi ?? '',
    ));
    TtsTextSlice? next;
    Object? lastError;
    final startedAt = DateTime.now();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        next = await source.advance().timeout(_advanceTimeout);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    final completedAt = DateTime.now();
    diagnostics.add(TtsSliceAdvanceCompleted(
      at: completedAt,
      engine: engineKind,
      elapsedMs: completedAt.difference(startedAt).inMilliseconds,
      nextCfi: next?.cfi ?? '',
    ));
    diagnostics.add(TtsPageTurnCompleted(
      at: completedAt,
      engine: engineKind,
      source: TtsPageTurnSource.sliceEnd,
      elapsedMs: completedAt.difference(audioEndedAt).inMilliseconds,
      animationMs: _pageTurnAnimationMs(),
    ));
    if (!_isActive(session) || generation != _advanceGeneration) return;
    if (next == null) {
      if (lastError != null) {
        diagnostics.add(TtsStallDetected(
          at: completedAt,
          engine: engineKind,
          stage: TtsStallStage.readerAdvance,
          elapsedMs: completedAt.difference(startedAt).inMilliseconds,
          action: 'surface-retryable-error',
        ));
        _publishFailure(
          session,
          TtsTextLoadError(
            engine: engineKind,
            message: 'Reader failed to advance to the next sentence',
            cause: lastError,
          ),
        );
      }
      return;
    }
    final nextSlice = next;
    recordEvent(TtsPageTurned(
      fromCfi: _lastReadCfi ?? '',
      at: DateTime.now(),
    ));
    final known = _slices.where((s) => s.index != null).toList();
    final nextIndex =
        known.isEmpty ? 0 : (known.map((s) => s.index!).reduce(math.max) + 1);
    if (!_slices.any((s) => s.key == nextSlice.key)) {
      _slices.add(nextSlice.copyWith(index: nextIndex));
    }
    await _refreshPageToken();
  }

  int _pageTurnAnimationMs() {
    final override = _pageTurnAnimationMsOverride;
    if (override != null) return override;
    // The webview paginator animates page turns in the 200-300ms range (see
    // assets/foliate-js/src/paginator.js animatePage: Math.max(200,
    // Math.min(300, 250 * distance/size))). Diagnostics count the upper bound
    // so the measured last-character→page-turn latency includes the effect.
    return 300;
  }

  String? _lastUtteranceIdOfSlice(TtsUtterance utterance) {
    for (final slice in _slices) {
      if ((slice.index ?? -1) == utterance.sliceIndex) {
        return _sliceLastUtteranceIds[slice.key];
      }
    }
    return null;
  }

  final Map<String, String?> _sliceLastUtteranceIds = <String, String?>{};

  int? _segmentSession;

  int _currentSegmentGapMs = 0;

  /// Page-boundary turns for utterances that end exactly at the page's last
  /// character (filled when a slice is expanded with a known page break).
  final Map<String, Future<void> Function()> _pageBreakTurns =
      <String, Future<void> Function()>{};

  final Set<String> _turnedBreaks = <String>{};

  // ============ Stall watchdog ============

  void _armStallWatchdog({
    required int session,
    required TtsStallStage stage,
    required String? utteranceId,
    required Duration timeout,
  }) {
    _stallTimer?.cancel();
    _stallStage = stage;
    _stallStartedAt = DateTime.now();
    _stallUtteranceId = utteranceId;
    _stallTimer = Timer(timeout, () => _onStallDetected(session));
  }

  void _cancelStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallStage = null;
    _stallStartedAt = null;
    _stallUtteranceId = null;
  }

  void _onStallDetected(int session) {
    if (!_isActive(session)) return;
    final stage = _stallStage;
    final startedAt = _stallStartedAt;
    if (stage == null || startedAt == null) return;
    if (_paused) {
      // A pause freezes the audio player, so no completion can arrive while
      // paused: the 25 s audioCompletion watchdog must not "recover" a segment
      // the user intentionally paused (it used to force-advance the reader and
      // desync the paused cursor). `pause()` cancels the watchdog and
      // `resume()` re-arms it; this guard covers the race between them.
      AnxLog.info('TTS[diag] stall ignored while paused stage=${stage.name} '
          '(utterance=$_stallUtteranceId)');
      _cancelStallWatchdog();
      return;
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    // Track forensics: when the watchdog fires, the position/duration/player
    // state of every audio track shows whether the segment was still playing
    // (and how far the fallback detection got) or whether the completion event
    // was lost after the media actually ended.
    final audio = _audio;
    var audioState = '';
    if (audio is TtsAudioOutputDiagnostics) {
      audioState =
          ' audio=[${(audio as TtsAudioOutputDiagnostics).debugState}]';
    }
    diagnostics.add(TtsStallDetected(
      at: DateTime.now(),
      engine: engineKind,
      stage: stage,
      elapsedMs: elapsedMs,
      action: 'recover',
    ));
    AnxLog.severe(
        'TTS[diag] stall detected stage=${stage.name} after ${elapsedMs}ms '
        '(utterance=$_stallUtteranceId)$audioState - recovering');
    recordEvent(TtsBoundaryGuarded(
      utteranceId: _stallUtteranceId ?? '',
      reason: 'stall-${stage.name}',
    ));
    _cancelStallWatchdog();
    switch (stage) {
      case TtsStallStage.audioCompletion:
        // The player completion callback was lost: treat the segment as
        // finished so the queue continues instead of hanging forever (MiMo's
        // "stuck until manual pause/resume").
        final completer = _segmentCompleter;
        _lastSegmentEndedAt = DateTime.now();
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        break;
      case TtsStallStage.audioStart:
      case TtsStallStage.synthesize:
        // Bounded synthesis retry already surfaces an error; nothing else to
        // do here.
        break;
      case TtsStallStage.readerAdvance:
        break;
    }
  }

  void _onSilentUtterance(int session) {
    skippedSegmentsNotifier.value = skippedSegmentsNotifier.value + 1;
    _publish(TtsSkippedUtterance(sessionId: session));
    AnxLog.severe(
        'TTS utterance produced no audio and was skipped (total: ${skippedSegmentsNotifier.value})');
  }

  // ============ Queue / slice management ============

  Future<void> _fillQueue(int session) async {
    while (_isActive(session) && _queue.length < _queueTarget) {
      final next = _nextUnexpandedSlice();
      if (next != null) {
        await _expandSlice(session, next);
        continue;
      }
      // No known-unexpanded text left: wait for the in-flight reader advance if
      // one is running (it may bring the next slice) instead of peeking from
      // a stale reader cursor and spinning.
      final advance = _advanceFuture;
      if (advance != null) {
        await advance;
        if (!_isActive(session)) return;
        if (playbackState.hasError) return;
        continue;
      }
      final grew = await _peekMore(session);
      if (!_isActive(session) || !grew) break;
    }
  }

  TtsTextSlice? _nextUnexpandedSlice() {
    for (final slice in _slices) {
      if (!_expandedSliceKeys.contains(slice.key)) return slice;
    }
    return null;
  }

  Future<bool> _peekMore(int session) async {
    final source = _source;
    if (source == null) return false;
    _peekWindow = math.max(_peekWindow + 1, _slices.length + 1);
    final peeked = await source.peek(count: _peekWindow);
    if (!_isActive(session)) return false;
    final known = _slices.map((s) => s.key).toSet();
    var added = false;
    for (final slice in peeked) {
      if (known.contains(slice.key)) continue;
      known.add(slice.key);
      _slices.add(slice.copyWith(index: _slices.length));
      added = true;
    }
    return added;
  }

  Future<void> _expandSlice(int session, TtsTextSlice slice) async {
    _expandedSliceKeys.add(slice.key);
    final units = _foldWhitespaceUnits(splitTtsParagraph(
      paragraph: slice.toParagraph(),
      maxRequestChars: capabilities.maxRequestChars,
      firstSliceIndex: slice.index ?? 0,
    ));
    if (units.isEmpty) {
      _sliceLastUtteranceIds[slice.key] = null;
      return;
    }
    _queue.addAll(units);
    _sliceLastUtteranceIds[slice.key] = units.last.id;
  }

  /// Waits at most a short budget for a pending reader advance so the page
  /// break bridge can see the new slice. Playback continues from the prefetched
  /// slice afterwards, so a slow webview never freezes audio.
  Future<void> _awaitPendingAdvanceBriefly() async {
    final advance = _advanceFuture;
    if (advance == null) return;
    try {
      await advance.timeout(const Duration(milliseconds: 150));
    } catch (_) {
      // Slow/failed advance: fall back to sentence-end page turn.
    }
  }

  TtsTextSlice? _sliceForUtterance(TtsUtterance utterance) {
    for (final slice in _slices) {
      if ((slice.index ?? -1) == utterance.sliceIndex) return slice;
    }
    return null;
  }

  /// Splits the current slice at its page boundary right before its first unit
  /// starts playing, so the page turns on the page's last character.
  Future<TtsUtterance> _applyPageBreakBeforeSlice(
    int session,
    TtsUtterance utterance,
  ) async {
    final source = _source;
    if (source is! TtsPageTurnCapable) return utterance;
    final slice = _sliceForUtterance(utterance);
    if (slice == null) return utterance;
    try {
      final pageTurnSource = source as TtsPageTurnCapable;
      // Bounded: a busy webview must never delay the audio start by seconds.
      final pageBreak = await pageTurnSource
          .pageBreakFor(slice)
          .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      if (!_isActive(session) || pageBreak == null) return utterance;
      final sliceUnits = <TtsUtterance>[utterance];
      var take = 0;
      while (take < _queue.length &&
          _queue[take].sliceIndex == utterance.sliceIndex) {
        sliceUnits.add(_queue[take]);
        take++;
      }
      final split = _splitUnitsAtPageBreak(sliceUnits, pageBreak);
      if (split.isEmpty) return utterance;
      final tail = _queue.skip(take).toList();
      _queue
        ..clear()
        ..addAll(split.skip(1))
        ..addAll(tail);
      _sliceLastUtteranceIds[slice.key] = split.last.id;
      recordEvent(TtsBoundaryGuarded(
        utteranceId: utterance.id,
        reason: 'page-break-split@${pageBreak.charOffsetInSlice}',
      ));
      return split.first;
    } catch (e) {
      AnxLog.info('TTS page-break split failed: $e');
      return utterance;
    }
  }

  /// Splits the unit that contains [pageBreak] and records a page-turn action
  /// for the part that ends exactly at the page's last character.
  List<TtsUtterance> _splitUnitsAtPageBreak(
    List<TtsUtterance> units,
    TtsPageBreak pageBreak,
  ) {
    final offset = pageBreak.charOffsetInSlice;
    final result = <TtsUtterance>[];
    var turnScheduled = false;
    for (final unit in units) {
      if (turnScheduled) {
        result.add(unit);
        continue;
      }
      final start = unit.range.start;
      final end = unit.range.end;
      if (offset > start && offset < end) {
        final rel = offset - start;
        final firstText = unit.text.substring(0, rel);
        final secondText = unit.text.substring(rel);
        if (firstText.trim().isNotEmpty) {
          final firstPart = TtsUtterance(
            id: '${unit.id}.a',
            paragraphId: unit.paragraphId,
            unitIndex: unit.unitIndex,
            text: firstText,
            range: TtsCharRange(start: start, end: offset),
            boundaryBefore: unit.boundaryBefore,
            cfi: unit.cfi,
            isParagraphStart: unit.isParagraphStart,
            sliceIndex: unit.sliceIndex,
          );
          result.add(firstPart);
          _pageBreakTurns[firstPart.id] = () => _turnPageForBreak(pageBreak);
          turnScheduled = true;
        }
        final secondPart = TtsUtterance(
          id: '${unit.id}.b',
          paragraphId: unit.paragraphId,
          unitIndex: unit.unitIndex,
          text: secondText,
          range: TtsCharRange(start: offset, end: end),
          boundaryBefore: TtsBoundaryBefore.hardCut,
          cfi: unit.cfi,
          isParagraphStart: false,
          sliceIndex: unit.sliceIndex,
        );
        if (secondText.trim().isNotEmpty) {
          result.add(secondPart);
        }
        continue;
      }
      if (offset == end) {
        // Page ends exactly at this unit's last character.
        result.add(unit);
        _pageBreakTurns[unit.id] = () => _turnPageForBreak(pageBreak);
        turnScheduled = true;
        continue;
      }
      result.add(unit);
    }
    return result;
  }

  Future<void> _turnPageForBreak(TtsPageBreak pageBreak) async {
    final source = _source;
    if (source is TtsPageTurnCapable) {
      await (source as TtsPageTurnCapable).turnPageFromBreak(pageBreak);
    }
  }

  /// Fold whitespace-only units (leading indentation, stray line breaks) into
  /// the following spoken unit. Engines must never receive an empty-text
  /// request (it produces silence) and dropping the unit would lose characters
  /// at the paragraph head -the reported "paragraph loses its first 2-3
  /// characters" class of bug.
  List<TtsUtterance> _foldWhitespaceUnits(List<TtsUtterance> units) {
    if (units.length <= 1) return units;
    final folded = <TtsUtterance>[];
    TtsUtterance? pendingWhitespace;
    for (final unit in units) {
      if (unit.text.trim().isEmpty) {
        pendingWhitespace = pendingWhitespace == null
            ? unit
            : _mergeUtterances(pendingWhitespace, unit);
        continue;
      }
      if (pendingWhitespace != null) {
        folded.add(_mergeUtterances(pendingWhitespace, unit));
        pendingWhitespace = null;
      } else {
        folded.add(unit);
      }
    }
    if (pendingWhitespace != null) {
      if (folded.isNotEmpty) {
        folded[folded.length - 1] =
            _mergeUtterances(folded.last, pendingWhitespace);
      } else {
        folded.add(pendingWhitespace);
      }
    }
    return folded;
  }

  TtsUtterance _mergeUtterances(TtsUtterance first, TtsUtterance second) {
    return TtsUtterance(
      id: first.id,
      paragraphId: first.paragraphId,
      unitIndex: first.unitIndex,
      text: '${first.text}${second.text}',
      range: TtsCharRange(
        start: first.range.start,
        end: second.range.end,
      ),
      boundaryBefore: first.boundaryBefore,
      cfi: first.cfi ?? second.cfi,
      isParagraphStart: first.isParagraphStart,
      sliceIndex: first.sliceIndex,
    );
  }

  // ============ Public playback API ============

  @override
  Future<void> speak({TtsResumeAnchor? anchor, int warmUpUnits = 0}) async {
    if (_disposed) return;
    if (anchor != null) _pendingAnchor = anchor;
    // Serialize a play() that races an async init() instead of starting a
    // second session.
    final initFuture = _initFuture;
    if (initFuture != null) {
      await initFuture;
      if (_disposed) return;
    }
    final phase = playbackState.phase;
    if (phase == TtsPlaybackPhase.paused) {
      await resume();
      return;
    }
    if (phase == TtsPlaybackPhase.error || phase == TtsPlaybackPhase.empty) {
      await retry();
      return;
    }
    if (_runnerActive) return;
    if (_source == null) {
      _publishFailure(
        _session,
        TtsInitializationError(
            engine: engineKind, message: 'No text source bound'),
      );
      return;
    }
    if (_audio == null ||
        phase == TtsPlaybackPhase.idle ||
        phase == TtsPlaybackPhase.stopped ||
        phase == TtsPlaybackPhase.stopping ||
        phase == TtsPlaybackPhase.switchingEngine) {
      _warmUpUnits = warmUpUnits;
      await _beginSession(anchor: _pendingAnchor);
      return;
    }
    _paused = false;
    _warmUpUnits = warmUpUnits;
    _startRunner(_session);
  }

  @override
  Future<void> pause() async {
    final session = _session;
    if (!_isActive(session)) return;
    final phase = playbackState.phase;
    if (phase != TtsPlaybackPhase.playing &&
        phase != TtsPlaybackPhase.buffering) {
      return;
    }
    _publish(TtsPauseRequested(sessionId: session));
    _paused = true;
    try {
      await _withAudioOps(() async {
        await _audio?.pause();
      });
    } catch (e) {
      _publishFailure(
        session,
        TtsAudioOutputError(
          engine: engineKind,
          message: 'Failed to pause audio output',
          stage: TtsStage.pause,
          cause: e,
        ),
      );
      return;
    }
    final cursor = _pausedCursorFor(_currentUtterance);
    _publish(TtsPlaybackPaused(sessionId: session, cursor: cursor));
    // While paused no audio completion can arrive; keeping the audioCompletion
    // watchdog armed made it fire after 25 s and force-advance the reader
    // behind the user's back. It is re-armed by `resume()`.
    _cancelStallWatchdog();
    unawaited(_refreshPageToken());
    recordEvent(TtsPaused(pageCfi: _lastPageToken ?? ''));
  }

  TtsPlaybackCursor _pausedCursorFor(TtsUtterance? utterance) {
    final current = playbackState.cursor;
    if (utterance == null) {
      return current ?? const TtsPlaybackCursor(utteranceId: '', charOffset: 0);
    }
    if (current != null && current.utteranceId == utterance.id) {
      return current;
    }
    return TtsPlaybackCursor.startOf(utterance);
  }

  @override
  Future<void> resume() async {
    final session = _session;
    if (!_isActive(session)) return;
    if (playbackState.phase != TtsPlaybackPhase.paused) return;
    _publish(TtsResumeRequested(sessionId: session));
    final current = _currentUtterance;
    final cursor = _pausedCursorFor(current);
    recordEvent(TtsResumed(
      action: TtsResumeAction.continueInPlace,
      anchorCfi: current?.cfi ?? _lastReadCfi ?? '',
    ));
    diagnostics.add(TtsDiagResumeRequested(
      at: DateTime.now(),
      engine: engineKind,
      utteranceId: current?.id,
      charOffset: cursor.charOffset,
    ));

    // Never restart from the page top on pause→resume: that was the reported
    // "resume skips the selected unread text and jumps to the next line".
    // Always continue the current utterance in place; if the player lost the
    // buffered segment, re-synthesize only the remaining text from the
    // word-calibrated cursor.
    _paused = false;
    var resumedInPlace = false;
    if (_audio != null && _segmentCompleter != null) {
      try {
        await _withAudioOps(() async {
          await _audio?.resume();
        });
        resumedInPlace = true;
      } catch (e) {
        AnxLog.info('TTS audio resume failed, will re-synthesize: $e');
      }
    }
    if (!resumedInPlace) {
      _replayCurrent = true;
      _replayTextOverride =
          current == null ? null : resumeTextFromCursor(current.text, cursor);
      final completer = _segmentCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    } else if (_stallStage == null) {
      _armStallWatchdog(
        session: session,
        stage: TtsStallStage.audioCompletion,
        utteranceId: current?.id,
        timeout: _stallTimeout,
      );
    }
    diagnostics.add(TtsDiagResumed(
      at: DateTime.now(),
      engine: engineKind,
      utteranceId: current?.id,
      charOffset: cursor.charOffset,
      textOverride: !resumedInPlace,
    ));
    _publish(TtsPlaybackResumed(sessionId: session));
    _resumeGate?.complete();
    _resumeGate = null;
  }

  @override
  Future<void> stop() async {
    final previousSession = _session;
    _session = previousSession + 1;
    _paused = false;
    _runnerActive = false;
    _resumeGate?.complete();
    _resumeGate = null;
    final completer = _segmentCompleter;
    _segmentCompleter = null;
    _segmentSession = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (_machine.state.sessionId == previousSession) {
      _publish(TtsStopRequested(sessionId: previousSession));
      _publish(TtsPlaybackStopped(sessionId: previousSession));
    }
    await _completionSub?.cancel();
    _completionSub = null;
    final audio = _audio;
    _audio = null;
    _infraFuture = null;
    if (audio != null) {
      await _withAudioOps(() async {
        try {
          await audio.stop();
        } catch (e) {
          AnxLog.info('TTS audio stop failed: $e');
        }
        await audio.dispose();
      });
    }
    _queue.clear();
    _slices.clear();
    _expandedSliceKeys.clear();
    _sliceLastUtteranceIds.clear();
    _peekWindow = 0;
    _currentUtterance = null;
    _prefetched.clear();
    _pageBreakTurns.clear();
    _turnedBreaks.clear();
    _preloadedUtteranceId = null;
    _preloadedRate = null;
    _replayCurrent = false;
    _replayTextOverride = null;
    _advanceFuture = null;
    _advanceGeneration++;
    _currentSegmentGapMs = 0;
    _lastSegmentEndedAt = null;
    _cancelStallWatchdog();
    recordEvent(const TtsStopped(reason: 'stop'));
    final source = _source;
    if (source != null) {
      unawaited(source.clearHighlight());
    }
  }

  @override
  Future<void> prev() async {
    final source = _source;
    if (source == null) return;
    final wasActive = _runnerActive || playbackState.isPaused;
    await stop();
    final previous = await source.rewind();
    if (!wasActive) return;
    await speak(
      anchor: previous?.cfi == null
          ? null
          : TtsResumeAnchor(
              cfi: previous!.cfi!, reason: TtsResumeReason.userRequested),
    );
  }

  @override
  Future<void> next() async {
    final source = _source;
    if (source == null) return;
    final wasActive = _runnerActive || playbackState.isPaused;
    await stop();
    final nextSlice = await source.advance();
    if (!wasActive) return;
    await speak(
      anchor: nextSlice?.cfi == null
          ? null
          : TtsResumeAnchor(
              cfi: nextSlice!.cfi!, reason: TtsResumeReason.userRequested),
    );
  }

  @override
  Future<void> restart() async {
    await stop();
    await speak();
  }

  @override
  Future<void> retry() async {
    final phase = playbackState.phase;
    if (phase != TtsPlaybackPhase.error && phase != TtsPlaybackPhase.empty) {
      return;
    }
    final session = _session;
    _publish(TtsRetryRequested(sessionId: session));
    final source = _source;
    if (source == null) {
      _publishFailure(
        session,
        TtsInitializationError(
            engine: engineKind, message: 'No text source bound'),
      );
      return;
    }
    final utterance = _currentUtterance;
    final anchor = utterance?.cfi ?? _lastReadCfi;
    if (_audio != null && utterance != null) {
      // Continue in place: keep queue/cursor, only retry the failed stage.
      _paused = false;
      final newSession = ++_session;
      _publish(TtsSessionStarted(
        sessionId: newSession,
        engine: engineKind,
        rate: rate,
        anchor: anchor == null
            ? null
            : TtsResumeAnchor(
                cfi: anchor, reason: TtsResumeReason.userRequested),
      ));
      try {
        await _ensureInfrastructure();
        if (!_isActive(newSession)) return;
        _publish(TtsEngineReady(sessionId: newSession));
        _startRunner(newSession, locate: false);
      } catch (e) {
        _publishFailure(newSession, _toError(e, TtsStage.initialize));
      }
      return;
    }
    await _beginSession(
      anchor: anchor == null
          ? null
          : TtsResumeAnchor(cfi: anchor, reason: TtsResumeReason.userRequested),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _engine?.dispose();
    _engine = null;
    await _source?.dispose();
    _source = null;
  }

  @override
  TtsResumeAnchor? captureResumeAnchor({
    TtsResumeReason reason = TtsResumeReason.engineSwitched,
  }) {
    return buildTtsResumeAnchor(
      cursor: playbackState.cursor,
      utterance: _currentUtterance,
      cfi: _lastReadCfi,
      reason: reason,
      pageToken: _lastPageToken,
    );
  }

  @override
  Future<List<TtsVoice>> getVoices() async => _activeEngine.voices();

  @override
  Future<Uint8List> synthesizePreview(String text, String? voice) async {
    final engine = _activeEngine;
    return engine.synthesize(TtsSynthesisRequest(
      text: text,
      config: TtsSpeechConfig(
        rate: rate,
        pitch: pitch,
        volume: volume,
        voice: voice,
      ),
      engine: engineKind,
      utteranceId: 'preview',
    ));
  }

  @override
  Future<void> speakPreview(String text) async {
    final bytes = await speakWithVoice(text, '');
    if (bytes.isEmpty) {
      throw TtsSynthesisError(
        engine: engineKind,
        message: 'Engine returned empty audio for preview text',
      );
    }
  }

  /// For testing a specific voice in settings.
  /// Returns the synthesized audio so callers can react to empty results.
  Future<Uint8List> speakWithVoice(String content, String voice) async {
    await stop();
    final engine = _activeEngine;
    final bytes = await engine.synthesize(TtsSynthesisRequest(
      text: content,
      config: TtsSpeechConfig(
        rate: rate,
        pitch: pitch,
        volume: volume,
        voice: voice.isEmpty ? null : voice,
      ),
      engine: engineKind,
    ));
    if (bytes.isEmpty) return bytes;
    final audio = _createAudioOutput();
    _previewAudio?.dispose();
    _previewAudio = audio;
    try {
      await audio.initialize(warmUp: _shouldWarmUp());
      await audio.setVolume(volume);
      await audio.prepare(TtsAudioRequest(
        bytes: bytes,
        mimeType: _mimeType(),
      ));
      await audio.start(
        playbackRate: ttsRateToMultiplier(rate),
        applyRate: !capabilities.appliesRateOnServer,
      );
      unawaited(disposePreviewAudioWhenDone(
        audio.completions,
        timeout: const Duration(seconds: 30),
        isCurrent: () => identical(_previewAudio, audio),
        onDone: () => _previewAudio = null,
        dispose: audio.dispose,
      ));
    } catch (e) {
      AnxLog.info('TTS preview playback failed: $e');
      await audio.dispose();
    }
    return bytes;
  }

  TtsAudioOutput? _previewAudio;

  // ============ Helpers ============

  bool _isActive(int session) => !_disposed && session == _session;

  Future<void> _waitWhilePaused(int session) async {
    while (_paused && _isActive(session)) {
      _resumeGate ??= Completer<void>();
      await _resumeGate!.future;
    }
  }

  void _publish(TtsStateEvent event) {
    final result = _machine.apply(event);
    if (result.changed) {
      publishState(result.state);
    }
  }

  void _publishFailure(int session, TtsPlaybackError error) {
    if (!_isActive(session)) return;
    recordEvent(TtsPlaybackFailure(error: error));
    _publish(TtsPlaybackFailed(sessionId: session, error: error));
    AnxLog.severe(
        'TTS failure ${error.code}: ${error.message} (context: ${error.context})');
  }

  void _publishEmpty(int session) {
    if (!_isActive(session)) return;
    final error = TtsEmptyTextError(engine: engineKind);
    _publish(TtsEmptyDetected(sessionId: session, error: error));
    recordEvent(TtsPlaybackFailure(error: error));
  }

  TtsPlaybackError _toError(Object error, TtsStage stage) {
    if (error is TtsPlaybackError) return error;
    return TtsUnexpectedPlaybackError(
      engine: engineKind,
      stage: stage,
      message: 'Unexpected TTS failure',
      cause: error,
    );
  }

  String _mimeType() {
    final kind = engineKind;
    if (kind == TtsEngineKind.mimo) {
      try {
        final config = Prefs().getOnlineTtsConfig('mimo');
        final format = config['format']?.toString().toLowerCase();
        if (format == 'wav') return 'audio/wav';
      } catch (_) {
        // Preferences are not ready (tests): fall through to the default.
      }
      return 'audio/mpeg';
    }
    return 'audio/mpeg';
  }

  Future<void> _refreshPageToken() async {
    final source = _source;
    if (source == null) return;
    try {
      final token = await source.currentPageToken();
      if (token.isNotEmpty) _lastPageToken = token;
    } catch (_) {
      // Ignore: the page token is optional bookkeeping.
    }
    _updateReadingPosition();
  }

  void _updateReadingPosition() {
    final cfi = _lastReadCfi;
    if (cfi == null || cfi.isEmpty) return;
    readingPositionNotifier.value = TtsReadingPositionState(
      lastReadCfi: cfi,
      pageToken: _lastPageToken ?? '',
    );
  }
}

/// Waits for preview playback to finish (or time out) and then releases the
/// audio output.
///
/// The completion stream can close without emitting any event (dispose race);
/// `Stream.first` then throws "Bad state: No element", which must be swallowed
/// so it does not become an uncaught async error in the SEVERE log.
@visibleForTesting
Future<void> disposePreviewAudioWhenDone(
  Stream<void> completions, {
  required Duration timeout,
  required bool Function() isCurrent,
  required VoidCallback onDone,
  required Future<void> Function() dispose,
}) async {
  try {
    await completions.first.timeout(timeout, onTimeout: () {});
  } catch (_) {
    // Completion/close/timeout failures must not skip disposal.
  } finally {
    if (isCurrent()) onDone();
    await dispose();
  }
}

/// One pre-fetched audio payload waiting in the lookahead queue.
final class _PrefetchedAudio {
  const _PrefetchedAudio({required this.bytes, required this.rate});

  final Uint8List bytes;
  final double rate;
}
