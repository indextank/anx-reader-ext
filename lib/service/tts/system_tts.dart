import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/diagnostics/tts_diagnostics.dart';
import 'package:anx_reader/service/tts/engine/system/flutter_tts_native_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
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
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';

/// Production system (platform) TTS engine.
///
/// Design notes (see docs/tts-audit):
/// - [TtsNativeSpeechEngine] is injected, so the playback logic is platform
///   agnostic and unit-testable with a fake; the default factory is
///   [FlutterTtsNativeEngine].
/// - One sequential utterance loop (no prefetch): the reader text source is
///   advanced only after the *last* utterance of a slice finished, so a
///   sentence is never skipped and the reader cursor never runs ahead.
/// - Every async continuation is guarded by a session id (and by the playback
///   phase), so a completion callback from a paused/stopped/replaced session
///   can never restart playback.
/// - Pause/resume uses the native pause of the platform engine when available
///   (Windows: `ISpVoice::Pause` + `speak` while paused continues). Otherwise
///   pause is simulated by stopping the engine and keeping the (word
///   calibrated) cursor; resume re-speaks the remaining text.
/// - Rate/volume/pitch are applied through [changeRate] and the pre-utterance
///   [TtsNativeSpeechEngine.configure] call: the next sentence always uses the
///   latest rate and the currently spoken sentence is never restarted.
class SystemTts extends BaseTts {
  SystemTts._({TtsNativeSpeechEngine? engine}) : _injectedEngine = engine;

  static final SystemTts _instance = SystemTts._();

  /// Shared application instance (app-lifetime singleton, matching the
  /// [TtsFactory] contract).
  factory SystemTts() => _instance;

  /// Injectable instance for tests: a fake native engine (and a fake text
  /// source) keep the tests deterministic and free of platform channels.
  @visibleForTesting
  factory SystemTts.withEngine(
    TtsNativeSpeechEngine engine, {
    Duration? speakTimeout,
    Duration? advanceTimeout,
    int? pageTurnAnimationMs,
  }) {
    final tts = SystemTts._(engine: engine);
    if (speakTimeout != null) tts._speakTimeout = speakTimeout;
    if (advanceTimeout != null) tts._advanceTimeout = advanceTimeout;
    if (pageTurnAnimationMs != null) {
      tts._pageTurnAnimationMsOverride = pageTurnAnimationMs;
    }
    return tts;
  }

  final TtsNativeSpeechEngine? _injectedEngine;
  TtsNativeSpeechEngine? _engineInstance;

  /// Maximum time to wait for one native utterance before recovering with a
  /// stop + bounded re-speak from the current cursor (guard against a hung
  /// platform callback).
  Duration _speakTimeout = const Duration(seconds: 60);
  Duration _advanceTimeout = const Duration(seconds: 8);
  int? _pageTurnAnimationMsOverride;

  final TtsPlaybackStateMachine _machine = TtsPlaybackStateMachine();

  @override
  TtsPlaybackStateMachine get playbackMachine => _machine;

  TtsTextSource? _source;
  TtsResumeAnchor? _pendingAnchor;

  /// Incremented for every playback session. Async continuations capture it and
  /// silently return when a newer session (or a stop) replaced theirs.
  int _session = 0;

  bool _disposed = false;
  bool _initialized = false;

  bool _driverActive = false;
  int _driverToken = 0;
  Future<void>? _driver;

  List<TtsUtterance> _units = const <TtsUtterance>[];
  int _nextUnitIndex = 0;
  int _resumeCharOffset = 0;
  bool _simulatedPause = false;

  /// Page-boundary page turns for units that end at the page's last character.
  final Map<String, Future<void> Function()> _pageBreakTurns =
      <String, Future<void> Function()>{};
  final Set<String> _turnedBreaks = <String>{};

  /// Peeked next reader slice (prefetch) and the decoupled advance request.
  TtsTextSlice? _nextSlice;
  Future<void>? _peekNextFuture;
  Future<void>? _advanceFuture;
  bool _advanceInBackground = false;
  DateTime? _lastSegmentEndedAt;
  int _currentSegmentGapMs = 0;

  TtsTextSlice? _currentSlice;
  TtsUtterance? _currentUtterance;
  TtsPlaybackCursor? _cursor;
  String? _currentCfi;
  String? _currentPageToken;

  StreamSubscription<TtsNativeEvent>? _eventSub;

  /// Completes when an in-flight [init] finished preparing its session, so a
  /// [speak] call that races with initialization does not start a second
  /// session.
  Completer<void>? _initCompleter;

  /// Deduplicates concurrent engine initialization (voices + speak race).
  Future<void>? _engineInitFuture;

  TtsNativeSpeechEngine get _engine =>
      _engineInstance ??= _injectedEngine ?? FlutterTtsNativeEngine();

  /// Linux/web deliberately keep the legacy no-op behaviour: `flutter_tts` has
  /// no usable system voice there, and the old code returned before touching
  /// the plugin. Everything else is delegated to the injected engine.
  bool get _legacyNoop {
    if (kIsWeb) return true;
    try {
      return AnxPlatform.isLinux;
    } catch (_) {
      return false;
    }
  }

  // ============ Identity / capabilities ============

  @override
  TtsEngineKind get engineKind => TtsEngineKind.system;

  @override
  String get engineId => 'system';

  @override
  TtsEngineCapabilities get capabilities => _engine.capabilities;

  @override
  TtsTextSource? get textSource => _source;

  /// Test hook: completes when the current playback driver (utterance loop)
  /// ends. Awaiting it makes tests independent of timer-based pumping.
  @visibleForTesting
  Future<void> get currentSession => _driver ?? Future<void>.value();

  // ============ Audio settings ============

  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double value) {
    Prefs().ttsVolume = value.clamp(0.0, 1.0).toDouble();
    // Applying the new volume immediately never interrupts the current
    // sentence: the platform engine changes its output volume in place.
    unawaited(_applyConfigBestEffort());
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double value) {
    Prefs().ttsPitch = value;
    unawaited(_applyConfigBestEffort());
  }

  @override
  double get rate => Prefs().ttsRate;

  /// Legacy setter: delegates to the single rate path so there is exactly one
  /// place that persists the rate and records the change (no restart).
  /// Not declared by [BaseTts] (new code must call [changeRate]), kept for the
  /// existing settings/FAB call sites that assign `tts.rate = value`.
  set rate(double value) {
    unawaited(changeRate(value));
  }

  @override
  Future<void> changeRate(double value) async {
    final newRate = clampTtsRate(value);
    Prefs().ttsRate = newRate;
    recordEvent(TtsRateChanged(
      rate: newRate,
      effectiveMultiplier: ttsRateToMultiplier(newRate),
    ));
    _publish(TtsRateChangeRequested(sessionId: _session, rate: newRate));
    // Apply the new rate to the engine *without* interrupting the current
    // utterance: the next engine request uses it (per-utterance configure).
    await _applyConfigBestEffort();
  }

  TtsSpeechConfig _speechConfig({String? voiceOverride}) {
    final selectedVoice = voiceOverride ?? Prefs().getTtsVoiceModel(engineId);
    return TtsSpeechConfig(
      rate: rate,
      pitch: pitch,
      volume: volume,
      // An empty string means "use the platform default voice"; the adapter
      // resets the voice for that case.
      voice: selectedVoice,
    );
  }

  Future<void> _applyConfigBestEffort() async {
    if (_legacyNoop || !_initialized || _disposed) return;
    try {
      await _engine.configure(_speechConfig());
    } catch (_) {
      // A settings change must never break an active playback session; the
      // next utterance surfaces a hard engine failure if the engine is gone.
    }
  }

  // ============ Lifecycle ============

  @override
  Future<void> init({
    required TtsTextSource textSource,
    TtsResumeAnchor? anchor,
  }) async {
    _reviveIfDisposed();
    _source = textSource;
    _pendingAnchor = anchor;
    if (_legacyNoop) return;
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      // A new text source always starts a fresh session; an old driver/speak
      // continuation is cancelled by stop().
      await stop();
      _source = textSource;
      _pendingAnchor = anchor;
      await _beginSession(anchor: anchor, locate: false);
    } finally {
      if (identical(_initCompleter, completer)) {
        _initCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  Future<void> speak({TtsResumeAnchor? anchor, int warmUpUnits = 0}) async {
    // The native engine speaks one utterance at a time; there is no synthesis
    // queue to warm up, so [warmUpUnits] is intentionally ignored here.
    _reviveIfDisposed();
    if (_legacyNoop) return;
    if (anchor != null) _pendingAnchor = anchor;

    // A play intent can race the async init() (audio_service play is not
    // serialized with init). Wait for the prepared session instead of
    // starting a second one.
    final pendingInit = _initCompleter;
    if (pendingInit != null && !pendingInit.isCompleted) {
      await pendingInit.future;
      if (_disposed || _legacyNoop) return;
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
    if (phase == TtsPlaybackPhase.playing ||
        phase == TtsPlaybackPhase.buffering ||
        phase == TtsPlaybackPhase.resuming ||
        phase == TtsPlaybackPhase.pausing ||
        phase == TtsPlaybackPhase.stopping) {
      return;
    }
    if (_source == null) {
      _publishFailure(
        _session,
        TtsInitializationError(
          engine: engineKind,
          message: 'No text source bound to the system TTS engine',
        ),
      );
      return;
    }
    if (!_initialized ||
        phase == TtsPlaybackPhase.idle ||
        phase == TtsPlaybackPhase.stopped ||
        phase == TtsPlaybackPhase.switchingEngine) {
      await _beginSession(anchor: _pendingAnchor);
      return;
    }
    // init() already prepared this session (engine ready, phase loadingText):
    // only the text location + utterance loop remain.
    _startDriver(_session, locate: true);
  }

  Future<void> _beginSession({
    TtsResumeAnchor? anchor,
    bool locate = true,
    TtsTextSlice? startSlice,
  }) async {
    if (_disposed || _legacyNoop) return;
    final session = ++_session;
    _pendingAnchor = anchor;
    _resetPlaybackState();
    _publish(TtsSessionStarted(
      sessionId: session,
      engine: engineKind,
      rate: rate,
      anchor: anchor,
    ));
    recordEvent(TtsSpeakStarted(
      reason: anchor == null ? 'speak' : 'resume:${anchor.reason.name}',
    ));
    try {
      await _ensureEngineReady();
      if (!_isActive(session)) return;
      _publish(TtsEngineReady(sessionId: session));
      if (startSlice != null) {
        await _loadSlice(startSlice, session: session, queryPageBreak: false);
        _startDriver(session, locate: false);
        return;
      }
      if (!locate) return;
      _startDriver(session, locate: true);
    } catch (error) {
      if (_isActive(session)) {
        _publishFailure(session, _toError(error, TtsStage.initialize));
      }
    }
  }

  Future<void> _ensureEngineReady() {
    if (_initialized) return Future<void>.value();
    final inFlight = _engineInitFuture;
    if (inFlight != null) return inFlight;
    final future = _initializeEngine();
    _engineInitFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_engineInitFuture, future)) _engineInitFuture = null;
    }).catchError((Object _) {
      // The original future propagates the error to every awaiter; this
      // cleanup chain must not report an unhandled asynchronous error.
    }));
    return future;
  }

  Future<void> _initializeEngine() async {
    final engine = _engine;
    await engine.initialize(config: _speechConfig());
    _initialized = true;
    _eventSub ??= engine.events.listen(
      _onNativeEvent,
      onError: (Object _) {
        // Typed failures travel through the awaited speak future; stream
        // errors are diagnostics only.
      },
    );
  }

  /// Engine events are diagnostic only: the utterance loop awaits the typed
  /// speak future, so no event (including a late one) can drive playback.
  void _onNativeEvent(TtsNativeEvent event) {
    if (_disposed) return;
    try {
      if (event.generation != _engine.generation) return;
    } catch (_) {
      return;
    }
    final utteranceId = _currentUtterance?.id ?? '';
    switch (event) {
      case TtsNativeCompleted():
        if (playbackState.phase == TtsPlaybackPhase.paused) {
          recordEvent(TtsBoundaryGuarded(
            utteranceId: utteranceId,
            reason: 'native-completion-while-paused',
          ));
        }
      case TtsNativeFailed(:final message):
        recordEvent(TtsBoundaryGuarded(
          utteranceId: utteranceId,
          reason: 'native-event-failed: $message',
        ));
      case TtsNativeStarted():
      case TtsNativeCancelled():
      case TtsNativePaused():
      case TtsNativeContinued():
        break;
    }
  }

  // ============ Utterance loop ============

  void _startDriver(int session, {bool locate = false}) {
    if (_disposed || !_isActive(session) || _driverActive) return;
    _driverActive = true;
    final token = ++_driverToken;
    if (locate) {
      _publish(TtsTextLocating(sessionId: session));
    }
    final future = _runSession(session, token, locate: locate);
    _driver = future;
    unawaited(future);
  }

  bool _isDriverCurrent(int session, int token) =>
      !_disposed && token == _driverToken && session == _session;

  Future<void> _runSession(
    int session,
    int token, {
    required bool locate,
  }) async {
    try {
      if (locate) {
        final anchor = _pendingAnchor;
        _pendingAnchor = null;
        final source = _source;
        if (source == null) {
          _publishFailure(
            session,
            TtsInitializationError(
              engine: engineKind,
              message: 'No text source bound to the system TTS engine',
            ),
          );
          return;
        }
        final located = await source.locate(resumeAtCfi: anchor?.cfi);
        if (!_isDriverCurrent(session, token)) return;
        if (located == null || located.isBlank) {
          _publishEmpty(session);
          return;
        }
        await _loadSlice(located,
            anchor: anchor, session: session, token: token);
        if (!_isDriverCurrent(session, token)) return;
        _schedulePeekNext(session, token);
      }
      await _playLoop(session, token);
    } catch (error) {
      if (_isDriverCurrent(session, token)) {
        _publishFailure(session, _toError(error, TtsStage.play));
      }
    } finally {
      if (token == _driverToken) {
        _driverActive = false;
        _driver = null;
      }
    }
  }

  Future<void> _playLoop(int session, int token) async {
    while (true) {
      if (!_isDriverCurrent(session, token)) return;
      if (_isHalted(playbackState.phase)) return;

      if (_nextUnitIndex >= _units.length) {
        final advanced = await _advanceToNextSlice(session, token);
        if (!advanced) return;
        continue;
      }

      final unit = _units[_nextUnitIndex];

      // The rate is applied before every utterance, so a change while the
      // previous sentence is still speaking takes effect on the next one.
      await _applyConfigBestEffort();
      if (!_isDriverCurrent(session, token)) return;
      if (_isHalted(playbackState.phase)) return;

      final pendingOffset = _resumeCharOffset;
      _resumeCharOffset = 0;
      final startOffset = pendingOffset > 0 && _cursor?.utteranceId == unit.id
          ? calibrateTtsResumeOffset(unit.text, pendingOffset)
          : 0;
      final startCursor = startOffset == 0
          ? ttsCursorAtStart(unit)
          : TtsPlaybackCursor(
              utteranceId: unit.id,
              charOffset: startOffset,
              paragraphCharOffset: unit.range.start + startOffset,
              sliceIndex: unit.sliceIndex,
            );
      final rawText = startOffset == 0
          ? unit.text
          : resumeTextFromCursor(unit.text, startCursor);
      // Never read sentence-final numeric annotations ([12]) aloud.
      final text = prepareTtsSpeechText(rawText).speechText;

      _currentUtterance = unit;
      _cursor = startCursor;
      _currentCfi = unit.cfi ?? _currentCfi;

      if (text.trim().isEmpty) {
        // Blank or annotation-only unit: no audio, but page-turn/slice-advance
        // bookkeeping still has to happen.
        _nextUnitIndex++;
        _afterUnitBoundary(unit, startCursor, DateTime.now());
        continue;
      }

      _publish(TtsUtteranceStarted(
        sessionId: session,
        utterance: unit,
        cursor: startCursor,
      ));
      recordEvent(TtsSentenceStarted(
        cfi: unit.cfi ?? _currentCfi ?? '',
        at: DateTime.now(),
      ));
      final startedAt = DateTime.now();
      diagnostics.add(TtsAudioSegmentStarted(
        at: startedAt,
        engine: engineKind,
        utteranceId: unit.id,
        queueDepth: _units.length - _nextUnitIndex,
        rate: rate,
        gapMs: _lastSegmentEndedAt == null
            ? 0
            : startedAt.difference(_lastSegmentEndedAt!).inMilliseconds,
      ));

      // Text/iterator may run ahead of the audio (the slice advance is
      // decoupled from playback). Repaint the reader selection right before
      // this unit becomes audible, for *every* unit: the highlight must match
      // the spoken sub-span exactly (annotations excluded), must replace the
      // previous sub-span, and must force the reader back to the sentence page
      // when the user manually paged away.
      await _highlightSpokenBounded(
        unit,
        rawText: rawText,
        baseOffset: unit.range.start + startOffset,
      );
      if (!_isDriverCurrent(session, token)) return;

      await _speakWithWatchdog(session, token, unit, text);
      if (!_isDriverCurrent(session, token)) return;

      // A pause/stop that happened while the engine was speaking settles the
      // native request as well. Its completion is stale: never advance.
      final phaseAfterSpeak = playbackState.phase;
      if (phaseAfterSpeak != TtsPlaybackPhase.playing) {
        recordEvent(TtsBoundaryGuarded(
          utteranceId: unit.id,
          reason: 'completion-ignored-${phaseAfterSpeak.name}',
        ));
        return;
      }

      final endedAt = DateTime.now();
      final endCursor = ttsCursorAtEnd(unit);
      _cursor = endCursor;
      _publish(TtsCursorAdvanced(sessionId: session, cursor: endCursor));
      _publish(TtsUtteranceCompleted(sessionId: session));
      diagnostics.add(TtsAudioSegmentCompleted(
        at: endedAt,
        engine: engineKind,
        utteranceId: unit.id,
        elapsedMs: endedAt.difference(startedAt).inMilliseconds,
        interSegmentGapMs: _currentSegmentGapMs,
      ));
      _lastSegmentEndedAt = endedAt;
      _nextUnitIndex++;
      _afterUnitBoundary(unit, endCursor, endedAt);
    }
  }

  /// Repaints the reader highlight for exactly the spoken part of [unit]
  /// (bounded so a busy webview cannot delay the native utterance indefinitely).
  Future<void> _highlightSpokenBounded(
    TtsUtterance unit, {
    required String rawText,
    required int baseOffset,
  }) async {
    final source = _source;
    if (source is! TtsHighlightCapable) return;
    final ranges = spokenRangesForText(rawText, baseOffset: baseOffset);
    final watch = Stopwatch()..start();
    var ok = false;
    try {
      ok = await (source as TtsHighlightCapable)
          .highlightSpoken(cfi: unit.cfi, ranges: ranges)
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      ok = false;
      AnxLog.info('System TTS highlight sync failed: $e');
    }
    watch.stop();
    diagnostics.add(TtsHighlightSynced(
      at: DateTime.now(),
      engine: engineKind,
      utteranceId: unit.id,
      elapsedMs: watch.elapsedMilliseconds,
      ok: ok,
    ));
  }

  /// Runs the native utterance with a timeout; a hung platform callback is
  /// recovered by stopping the engine and re-speaking the same text once
  /// (never skipping the current unread content).
  Future<void> _speakWithWatchdog(
    int session,
    int token,
    TtsUtterance unit,
    String text,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _engine.speak(text).timeout(_speakTimeout);
        return;
      } on TimeoutException catch (e) {
        if (!_isDriverCurrent(session, token)) return;
        diagnostics.add(TtsStallDetected(
          at: DateTime.now(),
          engine: engineKind,
          stage: TtsStallStage.audioCompletion,
          elapsedMs: _speakTimeout.inMilliseconds,
          action: attempt == 0 ? 'stop-and-respeak' : 'surface-error',
        ));
        AnxLog.severe('TTS[diag] system speak timeout for ${unit.id} '
            '(attempt ${attempt + 1})');
        try {
          await _engine.stop();
        } catch (_) {}
        if (attempt == 1) {
          _publishFailure(
            session,
            TtsAudioOutputError(
              engine: engineKind,
              message: 'System TTS did not finish speaking',
              cause: e,
              context: {'utterance': unit.id},
            ),
          );
          return;
        }
      } catch (error) {
        if (!_isDriverCurrent(session, token)) return;
        _publishFailure(session, _toError(error, TtsStage.synthesize));
        return;
      }
    }
  }

  /// Schedules the page turn for a unit that ends exactly at the page's last
  /// character. Runs decoupled from the audio so the next unit starts
  /// immediately.
  void _afterUnitBoundary(
    TtsUtterance unit,
    TtsPlaybackCursor endCursor,
    DateTime endedAt,
  ) {
    final turn = _pageBreakTurns[unit.id];
    if (turn != null && _turnedBreaks.add(unit.id)) {
      unawaited(_performPageBreakTurn(unit.id, turn, endedAt));
    }
  }

  Future<void> _performPageBreakTurn(
    String utteranceId,
    Future<void> Function() turn,
    DateTime audioEndedAt,
  ) async {
    final requestedAt = DateTime.now();
    diagnostics.add(TtsPageTurnRequested(
      at: requestedAt,
      engine: engineKind,
      source: TtsPageTurnSource.pageBreak,
      fromCfi: _currentCfi ?? '',
    ));
    try {
      await turn().timeout(_advanceTimeout);
      final completedAt = DateTime.now();
      diagnostics.add(TtsPageTurnCompleted(
        at: completedAt,
        engine: engineKind,
        source: TtsPageTurnSource.pageBreak,
        elapsedMs: completedAt.difference(audioEndedAt).inMilliseconds,
        animationMs: _pageTurnAnimationMs(),
      ));
      recordEvent(TtsPageTurned(
        fromCfi: _currentCfi ?? '',
        at: completedAt,
      ));
    } catch (e) {
      recordEvent(TtsBoundaryGuarded(
        utteranceId: utteranceId,
        reason: 'page-break-turn-failed',
      ));
      AnxLog.info('System TTS page-break turn failed: $e');
    }
  }

  int _pageTurnAnimationMs() {
    final override = _pageTurnAnimationMsOverride;
    if (override != null) return override;
    return 300;
  }

  /// Next slice: use the peeked prefetch and advance the reader cursor in the
  /// background, or fall back to an awaited advance at the end of the book.
  Future<bool> _advanceToNextSlice(int session, int token) async {
    final source = _source;
    if (source == null || _currentSlice == null) {
      _publishQueueExhausted(session);
      return false;
    }
    final prefetched = _nextSlice;
    _nextSlice = null;
    if (prefetched != null) {
      _startAdvanceInBackground(session, token);
      // Bounded wait so the page-break bridge sees the new slice while the
      // prefetched text is already available; a slow webview falls back to a
      // sentence-end page turn instead of stalling audio.
      await _awaitAdvanceBriefly();
      if (!_isDriverCurrent(session, token)) return false;
      await _loadSlice(prefetched, session: session, token: token);
      if (!_isDriverCurrent(session, token)) return false;
      _schedulePeekNext(session, token);
      return true;
    }
    final next = await _awaitAdvance(session, token);
    if (next == null) {
      _publishQueueExhausted(session);
      return false;
    }
    await _loadSlice(next, session: session, token: token);
    if (!_isDriverCurrent(session, token)) return false;
    _schedulePeekNext(session, token);
    return true;
  }

  Future<void> _awaitAdvanceBriefly() async {
    final advance = _advanceFuture;
    if (advance == null) return;
    try {
      await advance.timeout(const Duration(milliseconds: 150));
    } catch (_) {
      // Slow/failed advance: fall back to sentence-end page turn.
    }
  }

  Future<TtsTextSlice?> _awaitAdvance(int session, int token) async {
    final source = _source;
    if (source == null) return null;
    final requestedAt = DateTime.now();
    diagnostics.add(TtsSliceAdvanceRequested(
      at: requestedAt,
      engine: engineKind,
      fromCfi: _currentCfi ?? '',
    ));
    TtsTextSlice? next;
    Object? error;
    try {
      next = await source.advance().timeout(_advanceTimeout);
    } catch (e) {
      error = e;
    }
    final completedAt = DateTime.now();
    diagnostics.add(TtsSliceAdvanceCompleted(
      at: completedAt,
      engine: engineKind,
      elapsedMs: completedAt.difference(requestedAt).inMilliseconds,
      nextCfi: next?.cfi ?? '',
    ));
    if (!_isDriverCurrent(session, token)) return null;
    if (next == null && error != null) {
      _publishFailure(
        session,
        TtsTextLoadError(
          engine: engineKind,
          message: 'Reader failed to advance to the next sentence',
          cause: error,
        ),
      );
    }
    return next;
  }

  void _startAdvanceInBackground(int session, int token) {
    if (_advanceFuture != null || _advanceInBackground) return;
    _advanceInBackground = true;
    final fromCfi = _currentCfi ?? '';
    final requestedAt = DateTime.now();
    diagnostics.add(TtsSliceAdvanceRequested(
      at: requestedAt,
      engine: engineKind,
      fromCfi: fromCfi,
    ));
    final future = () async {
      final source = _source;
      if (source == null) return;
      TtsTextSlice? next;
      Object? error;
      try {
        next = await source.advance().timeout(_advanceTimeout);
      } catch (e) {
        error = e;
      }
      final completedAt = DateTime.now();
      diagnostics.add(TtsSliceAdvanceCompleted(
        at: completedAt,
        engine: engineKind,
        elapsedMs: completedAt.difference(requestedAt).inMilliseconds,
        nextCfi: next?.cfi ?? '',
      ));
      diagnostics.add(TtsPageTurnCompleted(
        at: completedAt,
        engine: engineKind,
        source: TtsPageTurnSource.sliceEnd,
        elapsedMs: completedAt.difference(requestedAt).inMilliseconds,
        animationMs: _pageTurnAnimationMs(),
      ));
      if (!_isDriverCurrent(session, token)) return;
      if (next == null && error != null) {
        AnxLog.info('System TTS background advance failed: $error');
        return;
      }
      recordEvent(TtsPageTurned(fromCfi: fromCfi, at: completedAt));
      _schedulePeekNext(session, token);
    }();
    _advanceFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_advanceFuture, future)) {
        _advanceFuture = null;
        _advanceInBackground = false;
      }
    }));
  }

  void _schedulePeekNext(int session, int token) {
    if (_peekNextFuture != null) return;
    final future = () async {
      final source = _source;
      if (source == null) return;
      try {
        final peeked = await source.peek(count: 1);
        if (!_isDriverCurrent(session, token)) return;
        if (peeked.isEmpty) return;
        final candidate = peeked.first;
        if (candidate.isBlank || candidate.key == _currentSlice?.key) return;
        _nextSlice = candidate;
      } catch (e) {
        AnxLog.info('System TTS peek-next failed: $e');
      }
    }();
    _peekNextFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_peekNextFuture, future)) _peekNextFuture = null;
    }));
  }

  /// Turns one reader slice into engine requests. The slice is located but not
  /// advanced: the reader cursor only moves after the slice finished, which is
  /// what prevents the "first sentence is skipped" regression.
  Future<void> _loadSlice(
    TtsTextSlice slice, {
    TtsResumeAnchor? anchor,
    int? session,
    int? token,
    bool queryPageBreak = true,
  }) async {
    _currentSlice = slice;
    _currentCfi = slice.cfi;
    _currentPageToken = slice.pageToken;
    _currentUtterance = null;
    _cursor = null;
    _pageBreakTurns.clear();
    _turnedBreaks.clear();

    final paragraph = slice.toParagraph(
      id: slice.key,
      pageToken: slice.pageToken,
    );
    var units = splitTtsParagraph(
      paragraph: paragraph,
      maxRequestChars: capabilities.maxRequestChars,
      firstSliceIndex: slice.index ?? 0,
    );

    // Split the sentence at the visible page boundary so the page can turn as
    // soon as the page's last character was spoken (not when the whole
    // sentence ends). Only possible while the reader TTS cursor is on this
    // slice; otherwise the bridge refuses and we fall back to sentence end.
    final source = _source;
    if (queryPageBreak && source is TtsPageTurnCapable && units.isNotEmpty) {
      try {
        final pageTurnSource = source as TtsPageTurnCapable;
        // Bounded: a busy webview must never delay the utterance by seconds.
        final pageBreak = await pageTurnSource
            .pageBreakFor(slice)
            .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
        if (session != null && token != null) {
          if (!_isDriverCurrent(session, token)) return;
        }
        if (pageBreak != null) {
          units = _splitUnitsAtPageBreak(units, pageBreak, pageTurnSource);
        }
      } catch (e) {
        AnxLog.info('System TTS page-break query failed: $e');
      }
    }

    _units = units;
    _nextUnitIndex = 0;
    _resumeCharOffset = 0;

    if (anchor == null || units.isEmpty) return;
    final anchorUtteranceId = anchor.utteranceId;
    if (anchorUtteranceId == null || anchorUtteranceId.isEmpty) return;
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      if (unit.id != anchorUtteranceId) continue;
      final offset = calibrateTtsResumeOffset(unit.text, anchor.charOffset);
      _nextUnitIndex = index;
      _resumeCharOffset = offset;
      _currentUtterance = unit;
      _cursor = TtsPlaybackCursor(
        utteranceId: unit.id,
        charOffset: offset,
        paragraphCharOffset: unit.range.start + offset,
        sliceIndex: unit.sliceIndex,
      );
      return;
    }
  }

  /// Splits the unit that contains [pageBreak] and registers a page turn for
  /// the part ending exactly at the page's last character.
  List<TtsUtterance> _splitUnitsAtPageBreak(
    List<TtsUtterance> units,
    TtsPageBreak pageBreak,
    TtsPageTurnCapable pageTurnSource,
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
          _pageBreakTurns[firstPart.id] =
              () => pageTurnSource.turnPageFromBreak(pageBreak);
          turnScheduled = true;
        }
        if (secondText.trim().isNotEmpty) {
          result.add(TtsUtterance(
            id: '${unit.id}.b',
            paragraphId: unit.paragraphId,
            unitIndex: unit.unitIndex,
            text: secondText,
            range: TtsCharRange(start: offset, end: end),
            boundaryBefore: TtsBoundaryBefore.hardCut,
            cfi: unit.cfi,
            isParagraphStart: false,
            sliceIndex: unit.sliceIndex,
          ));
        }
        continue;
      }
      if (offset == end) {
        result.add(unit);
        _pageBreakTurns[unit.id] =
            () => pageTurnSource.turnPageFromBreak(pageBreak);
        turnScheduled = true;
        continue;
      }
      result.add(unit);
    }
    return result;
  }

  // ============ Pause / resume ============

  @override
  Future<void> pause() async {
    if (_legacyNoop || _disposed) return;
    final session = _session;
    if (!_isActive(session)) return;
    final phase = playbackState.phase;
    if (phase != TtsPlaybackPhase.playing &&
        phase != TtsPlaybackPhase.buffering) {
      return;
    }
    _publish(TtsPauseRequested(sessionId: session));
    final cursor = _pauseCursor();
    _resumeCharOffset = cursor.charOffset;

    if (capabilities.supportsNativePause) {
      try {
        await _engine.pause();
      } catch (_) {
        if (!_isActive(session)) return;
        recordEvent(TtsBoundaryGuarded(
          utteranceId: cursor.utteranceId,
          reason: 'native-pause-failed-degraded-to-simulated',
        ));
        await _simulatePause(session, cursor);
        return;
      }
      if (!_isActive(session)) return;
      _simulatedPause = false;
      _publish(TtsPlaybackPaused(sessionId: session, cursor: cursor));
      recordEvent(TtsPaused(pageCfi: _currentPageToken ?? ''));
      return;
    }
    await _simulatePause(session, cursor);
  }

  Future<void> _simulatePause(int session, TtsPlaybackCursor cursor) async {
    _simulatedPause = true;
    try {
      await _engine.stop();
    } catch (_) {
      // The session is paused either way; a failing stop cannot un-pause it.
    }
    if (!_isActive(session)) return;
    _publish(TtsPlaybackPaused(sessionId: session, cursor: cursor));
    recordEvent(TtsPaused(pageCfi: _currentPageToken ?? ''));
  }

  @override
  Future<void> resume() async {
    if (_legacyNoop || _disposed) return;
    final session = _session;
    if (!_isActive(session)) return;
    if (playbackState.phase != TtsPlaybackPhase.paused) return;
    _publish(TtsResumeRequested(sessionId: session));
    recordEvent(TtsResumed(
      action: TtsResumeAction.continueInPlace,
      anchorCfi: _currentCfi ?? '',
    ));

    final driverActive = _driverActive;
    if (driverActive && capabilities.supportsNativePause && !_simulatedPause) {
      try {
        await _engine.resume();
      } catch (_) {
        if (!_isActive(session)) return;
        recordEvent(TtsBoundaryGuarded(
          utteranceId: _cursor?.utteranceId ?? '',
          reason: 'native-resume-failed-degraded-to-simulated',
        ));
        // Invalidate the blocked driver before settling the native request so
        // its callback can never advance playback, then re-speak from the
        // cursor (simulated-resume fallback).
        _driverToken++;
        _driverActive = false;
        try {
          await _engine.stop();
        } catch (_) {}
        if (!_isActive(session)) return;
        _simulatedPause = false;
        _publish(TtsPlaybackResumed(sessionId: session));
        _startDriver(session);
        return;
      }
      if (!_isActive(session)) return;
      // The driver is still awaiting the same engine request; it continues
      // from the native pause position and advances when it completes.
      _publish(TtsPlaybackResumed(sessionId: session));
      return;
    }

    // Simulated pause, or a pause that landed between two utterances: continue
    // by re-speaking the remaining text of the current utterance from the
    // word-calibrated cursor, then keep the queue going.
    _simulatedPause = false;
    _publish(TtsPlaybackResumed(sessionId: session));
    _startDriver(session);
  }

  TtsPlaybackCursor _pauseCursor() {
    final utterance = _currentUtterance;
    final cursor = _cursor ?? playbackState.cursor;
    if (utterance != null &&
        cursor != null &&
        cursor.utteranceId == utterance.id &&
        cursor.charOffset < utterance.text.length) {
      return cursor;
    }
    if (_nextUnitIndex >= 0 && _nextUnitIndex < _units.length) {
      return ttsCursorAtStart(_units[_nextUnitIndex]);
    }
    if (cursor != null) return cursor;
    final stateCursor = playbackState.cursor;
    if (stateCursor != null) return stateCursor;
    if (utterance != null) return ttsCursorAtEnd(utterance);
    return const TtsPlaybackCursor(utteranceId: '', charOffset: 0);
  }

  // ============ Stop / navigation ============

  @override
  Future<void> stop() async {
    final wasActive = _session > 0;
    final previousSession = _session;
    _session++;
    _pendingAnchor = null;
    _resetPlaybackState();
    if (!_legacyNoop) {
      try {
        await _engine.stop();
      } catch (_) {
        // The session is already cancelled; engine errors during stop are
        // diagnostics only.
      }
    }
    _publish(TtsStopRequested(sessionId: previousSession));
    _publish(TtsPlaybackStopped(sessionId: previousSession));
    recordEvent(const TtsStopped(reason: 'stop'));
    final source = _source;
    if (wasActive && source != null) {
      try {
        await source.clearHighlight();
      } catch (_) {
        // Dropping the highlight is cosmetic; stop must not fail because of it.
      }
    }
  }

  @override
  Future<void> prev() async {
    if (_legacyNoop || _disposed) return;
    final source = _source;
    if (source == null) return;
    await stop();
    TtsTextSlice? slice;
    try {
      slice = await source.rewind();
    } catch (_) {
      slice = null;
    }
    if (slice == null || slice.isBlank) {
      // Already at the beginning: keep the reader where it is.
      await _beginSession(anchor: null);
      return;
    }
    await _beginSession(anchor: null, locate: false, startSlice: slice);
  }

  @override
  Future<void> next() async {
    if (_legacyNoop || _disposed) return;
    final source = _source;
    if (source == null) return;
    await stop();
    TtsTextSlice? slice;
    try {
      slice = await source.advance();
    } catch (_) {
      slice = null;
    }
    if (slice == null || slice.isBlank) {
      // End of the book: a fresh session with the queue exhausted reports a
      // clean stopped state instead of speaking the last sentence again.
      await _beginSession(anchor: null, locate: false);
      _publishQueueExhausted(_session);
      return;
    }
    await _beginSession(anchor: null, locate: false, startSlice: slice);
  }

  @override
  Future<void> restart() async {
    if (_legacyNoop || _disposed) return;
    await stop();
    await _beginSession(anchor: null);
  }

  @override
  Future<void> retry() async {
    if (_legacyNoop || _disposed) return;
    final session = _session;
    if (session == 0 || !_isActive(session)) return;
    final phase = playbackState.phase;
    if (phase != TtsPlaybackPhase.error && phase != TtsPlaybackPhase.empty) {
      return;
    }
    _publish(TtsRetryRequested(sessionId: session));
    recordEvent(TtsSpeakStarted(reason: 'retry'));

    final hasPendingUtterance =
        _units.isNotEmpty && _nextUnitIndex < _units.length;
    if (hasPendingUtterance) {
      // Keep cursor + utterance: re-speak the remaining part of the failed
      // utterance, then continue the queue.
      final cursor = playbackState.cursor ?? _cursor;
      _resumeCharOffset =
          cursor != null && cursor.utteranceId == _units[_nextUnitIndex].id
              ? cursor.charOffset
              : 0;
      _startDriver(session);
      return;
    }
    await _beginSession(anchor: _pendingAnchor);
  }

  // ============ Settings preview / voices ============

  /// One-off preview for the settings page (no reader session).
  @override
  Future<void> speakPreview(String text) async {
    _reviveIfDisposed();
    if (_legacyNoop || text.trim().isEmpty) return;
    await stop();
    try {
      await _ensureEngineReady();
      await _engine.configure(_speechConfig());
      await _engine.speak(text);
    } catch (error) {
      throw _toError(error, TtsStage.synthesize);
    }
  }

  /// Legacy settings API: previews [content] with an explicit voice model.
  ///
  /// Kept because the settings page tests a specific voice before saving it;
  /// the saved voice is restored afterwards so normal playback is unaffected.
  Future<void> speakWithVoice(String content, String voiceShortName) async {
    _reviveIfDisposed();
    if (_legacyNoop || content.trim().isEmpty) return;
    await stop();
    try {
      await _ensureEngineReady();
      await _engine.configure(_speechConfig(voiceOverride: voiceShortName));
      await _engine.speak(content);
    } catch (error) {
      throw _toError(error, TtsStage.synthesize);
    } finally {
      await _applyConfigBestEffort();
    }
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    _reviveIfDisposed();
    if (_legacyNoop) return const <TtsVoice>[];
    try {
      await _ensureEngineReady();
      return await _engine.voices();
    } catch (_) {
      return const <TtsVoice>[];
    }
  }

  @override
  Future<Uint8List> synthesizePreview(String text, String? voice) async {
    throw UnsupportedError('System TTS does not return audio bytes');
  }

  // ============ Engine switching ============

  @override
  TtsResumeAnchor? captureResumeAnchor({
    TtsResumeReason reason = TtsResumeReason.engineSwitched,
  }) {
    if (_legacyNoop) return null;
    final cursor = _cursor ?? playbackState.cursor;
    final utterance = _anchorUtterance(cursor);
    final cfi = utterance?.cfi ??
        _currentCfi ??
        _currentSlice?.cfi ??
        playbackState.pendingAnchor?.cfi;
    return buildTtsResumeAnchor(
      cursor: cursor,
      utterance: utterance,
      cfi: cfi,
      reason: reason,
      pageToken: _currentPageToken,
    );
  }

  TtsUtterance? _anchorUtterance(TtsPlaybackCursor? cursor) {
    if (cursor != null) {
      for (final unit in _units) {
        if (unit.id == cursor.utteranceId) return unit;
      }
    }
    return _currentUtterance ?? playbackState.utterance;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    _session++;
    _resetPlaybackState();
    _engineInitFuture = null;
    final pendingInit = _initCompleter;
    _initCompleter = null;
    if (pendingInit != null && !pendingInit.isCompleted) {
      pendingInit.complete();
    }
    await _eventSub?.cancel();
    _eventSub = null;
    final engine = _engineInstance;
    _engineInstance = null;
    _initialized = false;
    try {
      await engine?.dispose();
    } catch (_) {
      // Shutdown is best effort.
    }
  }

  // ============ Helpers ============

  bool _isActive(int session) => !_disposed && session == _session;

  static bool _isHalted(TtsPlaybackPhase phase) {
    switch (phase) {
      case TtsPlaybackPhase.idle:
      case TtsPlaybackPhase.initializing:
      case TtsPlaybackPhase.pausing:
      case TtsPlaybackPhase.paused:
      case TtsPlaybackPhase.stopping:
      case TtsPlaybackPhase.stopped:
      case TtsPlaybackPhase.error:
      case TtsPlaybackPhase.empty:
      case TtsPlaybackPhase.switchingEngine:
        return true;
      case TtsPlaybackPhase.loadingText:
      case TtsPlaybackPhase.buffering:
      case TtsPlaybackPhase.playing:
      case TtsPlaybackPhase.resuming:
        return false;
    }
  }

  void _resetPlaybackState() {
    _driverToken++;
    _driverActive = false;
    _driver = null;
    _units = const <TtsUtterance>[];
    _nextUnitIndex = 0;
    _resumeCharOffset = 0;
    _currentSlice = null;
    _currentUtterance = null;
    _cursor = null;
    _currentCfi = null;
    _currentPageToken = null;
    _simulatedPause = false;
  }

  void _reviveIfDisposed() {
    if (!_disposed) return;
    _disposed = false;
    _initialized = false;
    _engineInitFuture = null;
    _eventSub?.cancel();
    _eventSub = null;
  }

  void _publish(TtsStateEvent event) {
    final result = _machine.apply(event);
    publishState(result.state);
  }

  void _publishFailure(int session, TtsPlaybackError error) {
    _publish(TtsPlaybackFailed(sessionId: session, error: error));
    recordEvent(TtsPlaybackFailure(error: error));
  }

  void _publishEmpty(int session) {
    final error = TtsEmptyTextError(engine: engineKind);
    _publish(TtsEmptyDetected(sessionId: session, error: error));
    recordEvent(TtsPlaybackFailure(error: error));
  }

  void _publishQueueExhausted(int session) {
    _publish(TtsQueueExhausted(sessionId: session));
    recordEvent(const TtsStopped(reason: 'queueExhausted'));
  }

  TtsPlaybackError _toError(Object error, TtsStage stage) {
    if (error is TtsNativeEngineException) {
      switch (error.stage) {
        case TtsStageIdForNative.initialize:
          return TtsInitializationError(
            engine: engineKind,
            message: error.message,
            cause: error.cause,
          );
        case TtsStageIdForNative.speak:
          return TtsSynthesisError(
            engine: engineKind,
            message: error.message,
            cause: error.cause,
          );
        case TtsStageIdForNative.pause:
          return TtsUnexpectedPlaybackError(
            engine: engineKind,
            stage: TtsStage.pause,
            message: error.message,
            cause: error.cause,
          );
        case TtsStageIdForNative.resume:
          return TtsUnexpectedPlaybackError(
            engine: engineKind,
            stage: TtsStage.resume,
            message: error.message,
            cause: error.cause,
          );
        case TtsStageIdForNative.stop:
          return TtsUnexpectedPlaybackError(
            engine: engineKind,
            stage: TtsStage.stop,
            message: error.message,
            cause: error.cause,
          );
        case TtsStageIdForNative.query:
          return TtsUnexpectedPlaybackError(
            engine: engineKind,
            stage: TtsStage.initialize,
            message: error.message,
            cause: error.cause,
          );
      }
    }
    if (error is TtsPlaybackError) return error;
    return TtsUnexpectedPlaybackError(
      engine: engineKind,
      stage: stage,
      message: '$error',
      cause: error,
    );
  }
}
