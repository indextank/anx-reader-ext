import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:flutter/foundation.dart';

/// UI-facing seam between the TTS panel widget and the real playback service.
///
/// The widget only ever talks to this interface. Production wiring lives in
/// `lib/providers/tts_playback_provider.dart` ([TtsPanelController] backed by
/// `TtsHandler`); widget tests inject a fake implementation so no audio plugin
/// or `TtsHandler` singleton is ever constructed.
///
/// The tri-state (loading / error / empty) is derived from
/// [TtsPlaybackState] only. Retry must never stop or restart playback: it is a
/// pure "continue from the current cursor" intent.
abstract interface class TtsPanelController {
  /// Live playback state; the panel rebuilds from this value.
  ValueListenable<TtsPlaybackState> get stateListenable;

  /// Current speech rate in flutter_tts units.
  double get rate;

  /// Current output volume.
  double get volume;

  /// Current output pitch.
  double get pitch;

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  /// Retries the failed stage while keeping the current cursor/session.
  Future<void> retry();

  /// Applies a new rate to the current and all following utterances.
  Future<void> changeRate(double rate);

  /// Migrates the reading cursor to another engine.
  Future<void> switchEngine(String serviceId);

  Future<void> playPrevious();

  Future<void> playNext();

  void setVolume(double volume);

  void setPitch(double pitch);
}
