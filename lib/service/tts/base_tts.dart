import 'dart:async';

import 'package:anx_reader/service/tts/diagnostics/tts_diagnostics.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';

/// Legacy coarse state kept for existing UI surfaces (FAB, audio session
/// handlers). New code must read [BaseTts.playbackState] instead; this enum is
/// derived from the typed state machine and cannot drift.
enum TtsStateEnum { playing, stopped, paused, continued }

/// Sealed model of one playback-lifecycle transition. Every state change
/// the engine can make (and every entry point that drives it) is a typed
/// event, which keeps the lifecycle observable and unit-testable without
/// going through untyped maps.
sealed class TtsPlaybackEvent {
  const TtsPlaybackEvent();
}

final class TtsSpeakStarted extends TtsPlaybackEvent {
  const TtsSpeakStarted({required this.reason});
  final String reason;
}

final class TtsPaused extends TtsPlaybackEvent {
  const TtsPaused({required this.pageCfi});
  final String pageCfi;
}

final class TtsResumed extends TtsPlaybackEvent {
  const TtsResumed({required this.action, required this.anchorCfi});
  final TtsResumeAction action;
  final String anchorCfi;
}

final class TtsEngineSwitched extends TtsPlaybackEvent {
  const TtsEngineSwitched({required this.serviceId});
  final String serviceId;
}

final class TtsRateChanged extends TtsPlaybackEvent {
  const TtsRateChanged({required this.rate, required this.effectiveMultiplier});
  final double rate;
  final double effectiveMultiplier;
}

final class TtsPageTurned extends TtsPlaybackEvent {
  const TtsPageTurned({required this.fromCfi, required this.at});
  final String fromCfi;
  final DateTime at;
}

final class TtsSentenceStarted extends TtsPlaybackEvent {
  const TtsSentenceStarted({required this.cfi, required this.at});
  final String cfi;
  final DateTime at;
}

final class TtsStopped extends TtsPlaybackEvent {
  const TtsStopped({required this.reason});
  final String reason;
}

final class TtsBoundaryGuarded extends TtsPlaybackEvent {
  const TtsBoundaryGuarded({
    required this.utteranceId,
    required this.reason,
  });
  final String utteranceId;
  final String reason;
}

final class TtsAnchorMigrated extends TtsPlaybackEvent {
  const TtsAnchorMigrated({required this.anchor});
  final TtsResumeAnchor anchor;
}

final class TtsPlaybackFailure extends TtsPlaybackEvent {
  const TtsPlaybackFailure({required this.error});
  final TtsPlaybackError error;
}

/// Typed, observable lifecycle log shared by every engine (system and
/// cloud). Tests assert on this stream; it also doubles as the manual
/// acceptance log (timestamps of page turns vs. sentence starts).
final class TtsPlaybackLog {
  final List<TtsPlaybackEvent> events = <TtsPlaybackEvent>[];

  void add(TtsPlaybackEvent event) => events.add(event);

  void clear() => events.clear();

  Iterable<T> whereType<T extends TtsPlaybackEvent>() => events.whereType<T>();
}

/// Common base for all TTS engines.
///
/// This class owns the observable playback state and the derived legacy
/// notifier so every engine publishes loading/error/empty/playing states the
/// same way. Subclasses own their engine-specific session/queue logic and call
/// [publishState] when the typed state machine advances.
abstract class BaseTts {
  BaseTts();

  // ============ Identity / capabilities ============

  /// Typed engine identity.
  TtsEngineKind get engineKind;

  /// Stable engine id (`system`, `aliyun`, `mimo`, ...).
  String get engineId;

  /// Explicit capabilities the pipeline/machine branch on.
  TtsEngineCapabilities get capabilities;

  // ============ Observable state ============

  late final ValueNotifier<TtsPlaybackState> _playbackStateNotifier =
      ValueNotifier<TtsPlaybackState>(
    TtsPlaybackState.idle(engine: engineKind, rate: rate),
  );

  late final ValueNotifier<TtsStateEnum> _ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  final TtsPlaybackLog _playbackLog = TtsPlaybackLog();

  /// Typed diagnostics recorder (request/response timings, audio callbacks,
  /// queue depth, page-turn latency, stalls, pause/resume). Mirrored to the
  /// app log so device runs can be replayed; inspectable from tests.
  final TtsDiagnostics diagnostics =
      TtsDiagnostics(sink: (line) => AnxLog.info(line));

  TtsDiagnostics get ttsDiagnostics => diagnostics;

  ValueNotifier<TtsPlaybackState> get playbackStateNotifier =>
      _playbackStateNotifier;

  TtsPlaybackState get playbackState => _playbackStateNotifier.value;

  /// Legacy coarse notifier, derived from [playbackState].
  @Deprecated('Use playbackStateNotifier and derive loading/error/empty from '
      'TtsPlaybackState. Kept for audio_service and FAB compatibility.')
  ValueNotifier<TtsStateEnum> get ttsStateNotifier => _ttsStateNotifier;

  TtsPlaybackLog get playbackLog => _playbackLog;

  TtsPlaybackCursor? get cursor => playbackState.cursor;

  TtsUtterance? get currentUtterance => playbackState.utterance;

  String? get currentUtteranceText => playbackState.utterance?.text;

  TtsPlaybackError? get lastError => playbackState.error;

  bool get isPlaying => playbackState.phase == TtsPlaybackPhase.playing;

  bool get isPaused => playbackState.phase == TtsPlaybackPhase.paused;

  /// Publishes a new state, rejecting stale session ids so an engine that
  /// resolves late cannot overwrite a newer session.
  @protected
  void publishState(TtsPlaybackState state) {
    final current = _playbackStateNotifier.value;
    if (state.sessionId < current.sessionId) return;
    _playbackStateNotifier.value = state;
    final legacy = _legacyStateFor(state.phase);
    if (_ttsStateNotifier.value != legacy) {
      _ttsStateNotifier.value = legacy;
    }
  }

  @protected
  void recordEvent(TtsPlaybackEvent event) => _playbackLog.add(event);

  /// Engine-owned state machine, exposed so the handler can push cross-engine
  /// intents (engine switch) through the same validated transitions.
  @protected
  TtsPlaybackStateMachine get playbackMachine;

  /// Applies a cross-engine intent to the typed state machine. Stale or
  /// invalid transitions are ignored by the machine itself.
  void applyPlaybackIntent(TtsStateEvent event) {
    final result = playbackMachine.apply(event);
    if (result.changed) {
      publishState(result.state);
    }
  }

  /// Settles an engine that was initialized but is not playing (for example
  /// after a settings-panel engine switch). Without this the UI would stay in
  /// the `loadingText` skeleton forever instead of showing the play controls.
  void markPreparedAsStopped() {
    final phase = playbackState.phase;
    if (phase != TtsPlaybackPhase.initializing &&
        phase != TtsPlaybackPhase.loadingText) {
      return;
    }
    final session = playbackState.sessionId;
    applyPlaybackIntent(TtsStopRequested(sessionId: session));
    applyPlaybackIntent(TtsPlaybackStopped(sessionId: session));
  }

  /// Typed engine switch failure published on the engine's own state machine
  /// so the panel can show an error with retry (cursor/anchor preserved).
  void publishEngineSwitchFailure(TtsPlaybackError error) {
    applyPlaybackIntent(TtsPlaybackFailed(
      sessionId: playbackState.sessionId,
      error: error,
    ));
  }

  static TtsStateEnum _legacyStateFor(TtsPlaybackPhase phase) {
    switch (phase) {
      case TtsPlaybackPhase.playing:
      case TtsPlaybackPhase.buffering:
      case TtsPlaybackPhase.resuming:
        return TtsStateEnum.playing;
      case TtsPlaybackPhase.paused:
      case TtsPlaybackPhase.pausing:
        return TtsStateEnum.paused;
      case TtsPlaybackPhase.idle:
      case TtsPlaybackPhase.initializing:
      case TtsPlaybackPhase.loadingText:
      case TtsPlaybackPhase.stopping:
      case TtsPlaybackPhase.stopped:
      case TtsPlaybackPhase.switchingEngine:
      case TtsPlaybackPhase.error:
      case TtsPlaybackPhase.empty:
        return TtsStateEnum.stopped;
    }
  }

  // ============ Audio settings ============

  double get volume;
  set volume(double volume);

  double get pitch;
  set pitch(double pitch);

  /// Current UI rate in flutter_tts units.
  double get rate;

  /// Unified rate entry point. Every engine must apply the new rate through
  /// this method so the current and all following utterances stay in sync.
  Future<void> changeRate(double rate);

  // ============ Playback API ============

  /// Bind the reader text source and optionally a resume anchor. Engines must
  /// not start speaking until [speak] is called.
  Future<void> init({
    required TtsTextSource textSource,
    TtsResumeAnchor? anchor,
  });

  /// Starts a new playback session. When [anchor] is given (engine switch or
  /// explicit resume), playback continues from that anchor instead of the
  /// current page start.
  ///
  /// [warmUpUnits] requests the engine to synthesize the first N utterances
  /// *before* the first segment becomes audible. Cloud engines are slower than
  /// real time for long sentences, so a cold start (for example right after an
  /// engine switch) otherwise runs the queue dry after the first sentence and
  /// produces a multi-second silent gap. Normal playback starts with 0: audio
  /// should begin as soon as the first sentence is ready.
  Future<void> speak({TtsResumeAnchor? anchor, int warmUpUnits = 0});

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Future<void> prev();

  Future<void> next();

  Future<void> restart();

  /// Retries the failed stage while keeping the current cursor, so a
  /// transient network/audio error never restarts the paragraph.
  Future<void> retry();

  Future<void> dispose();

  /// Anchor describing where playback currently is, for engine switching.
  TtsResumeAnchor? captureResumeAnchor({
    TtsResumeReason reason = TtsResumeReason.engineSwitched,
  });

  TtsTextSource? get textSource;

  Future<List<TtsVoice>> getVoices();

  /// Speaks a one-off preview text from the settings page (no reader session).
  Future<void> speakPreview(String text);

  /// Synthesizes a one-off preview and returns the audio (online engines).
  /// System engines may throw [UnsupportedError].
  Future<Uint8List> synthesizePreview(String text, String? voice);
}
