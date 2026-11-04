import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/engine/engine_kind_mapping.dart';
import 'package:anx_reader/service/tts/engine/flutter_tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/provider_tts_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:anx_reader/service/tts/models/tts_text_splitter.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_cursor.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
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
  })  : _engineResolver = engineResolver,
        _audioOutputFactory = audioOutputFactory,
        _windowsOverride = windowsOverride,
        _synthesisTimeout = synthesisTimeout ?? const Duration(seconds: 15),
        _maxRetries = maxRetries ?? 2;

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
  }) {
    final tts = OnlineTts._(
      engineResolver: engineResolver,
      audioOutputFactory: () => audioOutputFactory,
      windowsOverride: windowsOverride,
      synthesisTimeout: synthesisTimeout,
      maxRetries: maxRetries,
    );
    tts._rateOverride = initialRate;
    tts._engineKindOverride = engineKindOverride;
    tts._volumeOverride = volumeOverride;
    tts._pitchOverride = pitchOverride;
    return tts;
  }

  final TtsSynthesisEngine Function()? _engineResolver;
  final TtsAudioOutput Function()? _audioOutputFactory;
  final bool? _windowsOverride;
  final Duration _synthesisTimeout;
  final int _maxRetries;

  /// Test hook: avoids touching shared preferences before they are loaded.
  double? _rateOverride;

  TtsEngineKind? _engineKindOverride;

  double? _volumeOverride;
  double? _pitchOverride;

  static const int _queueTarget = 8;

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

  Uint8List? _prefetchedAudio;
  TtsUtterance? _prefetchedUtterance;
  double? _prefetchedRate;
  String? _preloadedUtteranceId;
  double? _preloadedRate;

  String? _replayTextOverride;
  bool _replayCurrent = false;

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
      _prefetchedAudio = null;
      _prefetchedUtterance = null;
      _prefetchedRate = null;
      _preloadedUtteranceId = null;
      _preloadedRate = null;
      final audio = _audio;
      if (audio != null) {
        try {
          await audio.discardPrepared();
        } catch (e) {
          AnxLog.info('TTS rate change prepare discard failed: $e');
        }
      }
      return;
    }

    // Player-side rate (MiMo): apply immediately so the current sentence is
    // affected too; every later utterance re-applies it after loading its
    // source (a new media source resets the player rate).
    final audio = _audio;
    if (audio != null) {
      try {
        await audio.setPlaybackRate(multiplier);
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
    _peekWindow = 0;
    _currentUtterance = null;
    _prefetchedAudio = null;
    _prefetchedUtterance = null;
    _prefetchedRate = null;
    _preloadedUtteranceId = null;
    _preloadedRate = null;
    _replayCurrent = false;
    _replayTextOverride = null;

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
      if (_queue.isEmpty) {
        _publish(TtsQueueExhausted(sessionId: session));
        recordEvent(TtsStopped(reason: 'queue-exhausted'));
        await _source?.clearHighlight();
        return;
      }

      final utterance = _queue.removeAt(0);
      _currentUtterance = utterance;
      if (utterance.text.trim().isEmpty) {
        _onSilentUtterance(session);
        continue;
      }

      final startCursor = TtsPlaybackCursor.startOf(utterance);
      _publish(TtsUtteranceBuffering(
        sessionId: session,
        utterance: utterance,
        cursor: startCursor,
      ));

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
      await _onUtteranceFinished(session, utterance);
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
    final prefetchedId = _prefetchedUtterance?.id;
    if (prefetchedId == utterance.id &&
        _prefetchedRate == rate &&
        _prefetchedAudio != null) {
      final bytes = _prefetchedAudio!;
      _prefetchedAudio = null;
      _prefetchedUtterance = null;
      _prefetchedRate = null;
      return bytes;
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
    final text = textOverride ?? utterance.text;
    final engine = _activeEngine;
    final config = TtsSpeechConfig(
      rate: rate,
      pitch: pitch,
      volume: volume,
    );
    Object? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (!_isActive(session)) return null;
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
        return bytes;
      } on TtsEngineSynthesisException catch (e) {
        lastError = e;
        if (e.isOversized && text.length > 1) {
          _splitAndRequeue(session, utterance, text);
          return null;
        }
        if (attempt >= _maxRetries) break;
      } catch (e) {
        lastError = e;
        if (attempt >= _maxRetries) break;
      }
      await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
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
    final alreadyPrepared = _preloadedUtteranceId == utterance.id &&
        _preloadedRate == rate &&
        audio.hasPrepared;
    if (!alreadyPrepared) {
      await audio.discardPrepared();
      await audio.prepare(TtsAudioRequest(
        bytes: bytes,
        mimeType: mime,
        utteranceId: utterance.id,
      ));
    }
    _preloadedUtteranceId = null;
    _preloadedRate = null;
    _segmentSession = session;
    _segmentCompleter = Completer<void>();
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
    try {
      await audio.start(
        playbackRate: ttsRateToMultiplier(rate),
        applyRate: !capabilities.appliesRateOnServer,
      );
    } catch (e) {
      _segmentCompleter?.complete();
      final error = TtsAudioOutputError(
        engine: engineKind,
        message: 'Audio output failed to start',
        cause: e,
        context: {'utterance': utterance.id},
      );
      recordEvent(TtsPlaybackFailure(error: error));
      _publishFailure(session, error);
    }
  }

  void _prebufferNext(int session) {
    if (_queue.isEmpty) return;
    final candidate = _queue.first;
    if (candidate.text.trim().isEmpty) return;
    // Drop a stale pre-fetched payload (different rate / different candidate)
    // instead of playing it later against the wrong cursor.
    if (_prefetchedUtterance != null &&
        (_prefetchedUtterance!.id != candidate.id || _prefetchedRate != rate)) {
      _prefetchedUtterance = null;
      _prefetchedAudio = null;
      _prefetchedRate = null;
    }
    if (_prefetchedUtterance != null) return;
    unawaited(_prebuffer(session, candidate));
  }

  Future<void> _prebuffer(int session, TtsUtterance candidate) async {
    try {
      final rateAtRequest = rate;
      final bytes = await _synthesizeBytes(session, candidate);
      if (!_isActive(session) || bytes == null || bytes.isEmpty) return;
      if (rate != rateAtRequest) return;
      _prefetchedUtterance = candidate;
      _prefetchedAudio = bytes;
      _prefetchedRate = rateAtRequest;
      final audio = _audio;
      if (audio != null &&
          audio.supportsPreload &&
          _preloadedUtteranceId != candidate.id) {
        await audio.discardPrepared();
        await audio.prepare(TtsAudioRequest(
          bytes: bytes,
          mimeType: _mimeType(),
          utteranceId: candidate.id,
        ));
        _preloadedUtteranceId = candidate.id;
        _preloadedRate = rateAtRequest;
      }
    } catch (_) {
      // Prefetch is best-effort; the main loop reports real failures.
    }
  }

  void _onAudioCompleted() {
    if (_disposed || _paused) return;
    if (_segmentSession != _session) return;
    final completer = _segmentCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _onUtteranceFinished(int session, TtsUtterance utterance) async {
    final lastOfSlice = _lastUtteranceIdOfSlice(utterance);
    if (lastOfSlice == null || lastOfSlice != utterance.id) return;
    await _advanceSlice(session);
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

  Future<void> _advanceSlice(int session) async {
    final source = _source;
    if (source == null) return;
    try {
      final next = await source.advance();
      if (!_isActive(session)) return;
      if (next == null) return;
      recordEvent(TtsPageTurned(
        fromCfi: _lastReadCfi ?? '',
        at: DateTime.now(),
      ));
      final known = _slices.where((s) => s.index != null).toList();
      final nextIndex =
          known.isEmpty ? 0 : (known.map((s) => s.index!).reduce(math.max) + 1);
      if (_slices.any((s) => s.key == next.key)) {
        return;
      }
      _slices.add(next.copyWith(index: nextIndex));
      await _refreshPageToken();
    } catch (e) {
      AnxLog.info('TTS advance slice failed: $e');
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
        _expandSlice(next);
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

  void _expandSlice(TtsTextSlice slice) {
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

  /// Fold whitespace-only units (leading indentation, stray line breaks) into
  /// the following spoken unit. Engines must never receive an empty-text
  /// request (it produces silence) and dropping the unit would lose characters
  /// at the paragraph head — the reported "paragraph loses its first 2-3
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
  Future<void> speak({TtsResumeAnchor? anchor}) async {
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
      await _beginSession(anchor: _pendingAnchor);
      return;
    }
    _paused = false;
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
    final audio = _audio;
    if (audio != null) {
      try {
        await audio.pause();
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
    }
    final cursor = _pausedCursorFor(_currentUtterance);
    _publish(TtsPlaybackPaused(sessionId: session, cursor: cursor));
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

    // The reader may have moved to another page while paused; never jump back
    // to the old page in that case.
    var visibility = false;
    final cfi = _lastReadCfi;
    final source = _source;
    if (cfi != null && cfi.isNotEmpty && source != null) {
      visibility = await source.isCfiVisible(cfi);
    }
    final action = resolveResumeAction(
      lastReadCfi: cfi,
      lastReadPositionVisible: visibility,
    );
    recordEvent(TtsResumed(action: action, anchorCfi: cfi ?? ''));
    if (action == TtsResumeAction.restartFromCurrentPageStart) {
      await stop();
      await speak();
      return;
    }

    _paused = false;
    final audio = _audio;
    var resumedInPlace = false;
    if (audio != null) {
      try {
        await audio.resume();
        resumedInPlace = true;
      } catch (e) {
        AnxLog.info('TTS audio resume failed, will re-synthesize: $e');
      }
    }
    if (!resumedInPlace) {
      _replayCurrent = true;
      final utterance = _currentUtterance;
      final cursor = playbackState.cursor;
      if (utterance != null && cursor != null) {
        _replayTextOverride = resumeTextFromCursor(utterance.text, cursor);
      }
      final completer = _segmentCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
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
      try {
        await audio.stop();
      } catch (e) {
        AnxLog.info('TTS audio stop failed: $e');
      }
      await audio.dispose();
    }
    _queue.clear();
    _slices.clear();
    _expandedSliceKeys.clear();
    _sliceLastUtteranceIds.clear();
    _peekWindow = 0;
    _currentUtterance = null;
    _prefetchedAudio = null;
    _prefetchedUtterance = null;
    _prefetchedRate = null;
    _preloadedUtteranceId = null;
    _preloadedRate = null;
    _replayCurrent = false;
    _replayTextOverride = null;
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

/// 等待预览播放完成（或超时）后释放音频输出。
///
/// completions 流可能在未发出任何事件的情况下关闭（dispose/竞态），
/// [Stream.first] 此时抛 "Bad state: No element"——必须吞掉，
/// 否则成为未捕获异步错误进入全局 SEVERE 日志。
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
    // 完成/关闭/超时之外的异常不影响释放路径。
  } finally {
    if (isCurrent()) onDone();
    await dispose();
  }
}
