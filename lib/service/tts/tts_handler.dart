import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/engine/engine_kind_mapping.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

/// Stateful TTS entry point shared by the reading page, the audio_service
/// handler and the settings page.
///
/// All playback state lives in the active [BaseTts] engine's typed state
/// machine; this class only forwards user/OS intents and migrates the reading
/// cursor when the engine changes.
class TtsHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final TtsFactory _ttsFactory = TtsFactory();

  static final TtsHandler _instance = TtsHandler._internal();

  factory TtsHandler() {
    return _instance;
  }

  TtsHandler._internal() {
    _initAudioSession();
  }

  BaseTts get tts => _ttsFactory.current;

  TtsTextSource? _textSource;

  /// Last text source bound by the reading page / context menu.
  TtsTextSource? get textSource => _textSource;

  ValueNotifier<TtsPlaybackState> get playbackStateNotifier =>
      tts.playbackStateNotifier;

  TtsPlaybackState get ttsPlaybackState => tts.playbackState;

  TtsPlaybackLog get playbackLog => tts.playbackLog;

  /// Binds the reader text source and prepares the current engine.
  Future<void> init({
    required TtsTextSource textSource,
    TtsResumeAnchor? anchor,
  }) async {
    _textSource = textSource;
    await tts.init(textSource: textSource, anchor: anchor);
    // Initialization is not playback: show the controls (or the preserved
    // cursor) instead of a permanent loading skeleton.
    tts.markPreparedAsStopped();
  }

  /// How many utterances the new engine synthesizes before the switch resumes
  /// playback. Cloud engines are slower than real time for long sentences, so a
  /// cold single-segment start is followed by a multi-second blank (field log:
  /// 4859 ms after MiMo→StepAudio). A two-segment lead keeps playback
  /// continuous; a longer lead would just delay the switch further.
  static const int _engineSwitchWarmUpUnits = 2;

  /// Switches the TTS engine while migrating the current reading cursor.
  ///
  /// The old engine captures its anchor *before* stopping; the new engine is
  /// initialized with that anchor and, when playback was active, continues
  /// from the current sentence instead of restarting at the page top.
  Future<void> switchTtsType(String serviceId) async {
    if (Prefs().ttsService == serviceId) return;
    final switchWatch = Stopwatch()..start();
    final anchor = tts.captureResumeAnchor(
      reason: TtsResumeReason.engineSwitched,
    );
    final previousEngine = tts;
    final wasActive = tts.isPlaying ||
        tts.isPaused ||
        ttsPlaybackState.phase == TtsPlaybackPhase.buffering ||
        ttsPlaybackState.phase == TtsPlaybackPhase.loadingText ||
        ttsPlaybackState.phase == TtsPlaybackPhase.initializing;

    // Loading state for the switch: the panel shows a skeleton while the new
    // engine initializes; the typed state machine rejects stale events.
    previousEngine.applyPlaybackIntent(TtsEngineSwitchStarted(
      sessionId: previousEngine.playbackState.sessionId,
      targetEngine: currentTtsEngineKind(serviceId),
    ));
    playbackLog.add(TtsEngineSwitched(serviceId: serviceId));
    try {
      await _ttsFactory.switchTtsType(serviceId);
      final source = _textSource;
      if (source != null) {
        // Re-bind the source so the new engine owns it (the old engine was
        // stopped and released its audio output).
        await tts.init(textSource: source, anchor: anchor);
      }
    } catch (e) {
      tts.publishEngineSwitchFailure(TtsEngineSwitchError(
        engine: tts.engineKind,
        message: 'Failed to switch TTS engine to $serviceId',
        cause: e,
        context: {'target': serviceId},
      ));
      return;
    }
    if (anchor != null) {
      playbackLog.add(TtsAnchorMigrated(anchor: anchor));
    }
    if (wasActive && _textSource != null) {
      final engine = tts;
      await tts.speak(
        anchor: anchor,
        warmUpUnits: _engineSwitchWarmUpUnits,
      );
      _logSwitchAudibleLatency(engine, serviceId, switchWatch);
    } else {
      tts.markPreparedAsStopped();
    }
  }

  /// Records the switch → first audible segment latency without blocking the
  /// switch. Field logs need this number to tell engine-switch cold start apart
  /// from steady-state provider throughput gaps.
  void _logSwitchAudibleLatency(
    BaseTts engine,
    String serviceId,
    Stopwatch watch,
  ) {
    final completer = Completer<void>();
    Timer? timeout;
    void listener() {
      final state = engine.playbackStateNotifier.value;
      if (state.phase == TtsPlaybackPhase.playing ||
          state.hasError ||
          state.isEmpty ||
          state.phase == TtsPlaybackPhase.stopped) {
        if (!completer.isCompleted) completer.complete();
      }
    }

    engine.playbackStateNotifier.addListener(listener);
    listener();
    timeout = Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(completer.future.whenComplete(() {
      timeout?.cancel();
      try {
        engine.playbackStateNotifier.removeListener(listener);
      } catch (_) {
        // Engine already disposed.
      }
      final elapsed = watch.elapsedMilliseconds;
      final state = engine.playbackState;
      if (state.phase == TtsPlaybackPhase.playing) {
        AnxLog.info('TTS[diag] engine.switch.audible service=$serviceId '
            'elapsedMs=$elapsed');
        if (elapsed > 3000) {
          AnxLog.severe('TTS[diag] engine switch to $serviceId took '
              '${elapsed}ms before the first audible segment');
        }
      } else {
        AnxLog.info('TTS[diag] engine.switch.no-audio service=$serviceId '
            'elapsedMs=$elapsed phase=${state.phase.name}');
      }
    }));
  }

  Future<void> retry() => tts.retry();

  Future<void> changeRate(double rate) => tts.changeRate(rate);

  Future<void> _initAudioSession() async {
    try {
      await _configureAudioSession();
    } catch (e) {
      // 桌面端 audio_session 无平台实现（MissingPluginException 等），
      // 初始化失败不应成为未捕获异步错误。
      AnxLog.info('TTS audio session unavailable: $e');
    }
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;

    final allowMix = Prefs().allowMixWithOtherAudio;

    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: allowMix
          ? AVAudioSessionCategoryOptions.mixWithOthers
          : AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    ));
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Keep the previous behavior: system interruptions don't force pause.
      } else {
        switch (event.type) {
          case AudioInterruptionType.pause:
          case AudioInterruptionType.duck:
            if (!tts.isPlaying &&
                ttsPlaybackState.phase == TtsPlaybackPhase.paused) {
              play();
            }
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });
    session.becomingNoisyEventStream.listen((_) {
      if (tts.isPlaying) pause();
    });
  }

  @override
  Future<void> play() async {
    final session = await AudioSession.instance;
    if (await session.setActive(true)) {
      playbackState.add(playbackState.value.copyWith(
        controls: [MediaControl.pause, MediaControl.stop],
        processingState: AudioProcessingState.ready,
        playing: true,
      ));
    }

    final item = MediaItem(
      id: epubPlayerKey.currentState!.chapterTitle,
      title: epubPlayerKey.currentState!.chapterTitle,
      album: epubPlayerKey.currentState!.book.title,
      artist: epubPlayerKey.currentState!.book.author,
      // Use -1 to tell system not to render a progress bar.
      duration: const Duration(milliseconds: -1),
      artUri: Uri.tryParse(
          'file://${epubPlayerKey.currentState!.book.coverFullPath}'),
    );

    queue.add([item]);
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      processingState: AudioProcessingState.ready,
      playing: true,
      queueIndex: 0,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
    ));

    final phase = ttsPlaybackState.phase;
    switch (phase) {
      case TtsPlaybackPhase.paused:
        await tts.resume();
        break;
      case TtsPlaybackPhase.error:
      case TtsPlaybackPhase.empty:
        await tts.retry();
        break;
      case TtsPlaybackPhase.playing:
      case TtsPlaybackPhase.buffering:
      case TtsPlaybackPhase.resuming:
        // Already playing: nothing to do.
        break;
      case TtsPlaybackPhase.idle:
      case TtsPlaybackPhase.initializing:
      case TtsPlaybackPhase.loadingText:
      case TtsPlaybackPhase.pausing:
      case TtsPlaybackPhase.stopping:
      case TtsPlaybackPhase.stopped:
      case TtsPlaybackPhase.switchingEngine:
        await tts.speak();
        break;
    }
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.play, MediaControl.stop],
      queueIndex: queue.value.isNotEmpty ? 0 : null,
      processingState: AudioProcessingState.ready,
      playing: false,
    ));
    await tts.pause();
  }

  @override
  Future<void> stop() async {
    playbackState.add(playbackState.value.copyWith(
      controls: [],
      queueIndex: null,
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await tts.stop();
    epubPlayerKey.currentState?.ttsStop();
  }

  @override
  Future<void> skipToNext() async {
    await playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await playPrevious();
  }

  Future<void> playPrevious() async {
    await tts.prev();
  }

  Future<void> playNext() async {
    await tts.next();
  }

  @Deprecated('Use playbackStateNotifier; kept for legacy UI callbacks.')
  ValueNotifier<TtsStateEnum> get ttsStateNotifier => tts.ttsStateNotifier;

  bool get isPlaying => tts.isPlaying;

  set volume(double volume) {
    tts.volume = volume;
  }

  double get volume => tts.volume;

  set pitch(double pitch) {
    tts.pitch = pitch;
  }

  double get pitch => tts.pitch;

  double get rate => tts.rate;

  /// Legacy setter: delegates to the unified rate path.
  set rate(double rate) {
    unawaited(tts.changeRate(rate));
  }
}
