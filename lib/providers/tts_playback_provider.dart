import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/widgets/reading_page/tts_panel_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_playback_provider.g.dart';

/// Production [TtsPanelController] backed by the [TtsHandler] singleton.
///
/// It is only ever constructed by [ttsPanelControllerProvider]; widget tests
/// override that provider with a fake, so importing this file never touches
/// the audio plugins.
class TtsHandlerPanelController implements TtsPanelController {
  TtsHandlerPanelController({TtsHandler? handler})
      : _handler = handler ?? TtsHandler();

  final TtsHandler _handler;

  @override
  ValueListenable<TtsPlaybackState> get stateListenable =>
      _handler.playbackStateNotifier;

  @override
  double get rate => _handler.rate;

  @override
  double get volume => _handler.volume;

  @override
  double get pitch => _handler.pitch;

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> retry() => _handler.retry();

  @override
  Future<void> changeRate(double rate) => _handler.changeRate(rate);

  @override
  Future<void> switchEngine(String serviceId) =>
      _handler.switchTtsType(serviceId);

  @override
  Future<void> playPrevious() => _handler.playPrevious();

  @override
  Future<void> playNext() => _handler.playNext();

  @override
  void setVolume(double volume) => _handler.volume = volume;

  @override
  void setPitch(double pitch) => _handler.pitch = pitch;
}

/// Injected controller provider.
///
/// Production reads the real [TtsHandler]; widget tests override it with a
/// fake controller and therefore never instantiate [TtsHandler].
final ttsPanelControllerProvider = Provider<TtsPanelController>((ref) {
  return TtsHandlerPanelController();
});

/// Bridges the controller's [ValueListenable] playback state into Riverpod.
///
/// The state machine (and therefore [TtsPlaybackState]) is the single source
/// of truth for loading/error/empty; this notifier only mirrors it so any
/// Riverpod consumer can `ref.watch` playback state without touching the
/// audio layer.
@riverpod
class TtsPlaybackStateNotifier extends _$TtsPlaybackStateNotifier {
  @override
  TtsPlaybackState build() {
    final controller = ref.watch(ttsPanelControllerProvider);
    final listenable = controller.stateListenable;

    void sync() {
      state = listenable.value;
    }

    listenable.addListener(sync);
    ref.onDispose(() => listenable.removeListener(sync));
    return listenable.value;
  }
}

/// The public playback-state provider name for the TTS panel.
///
/// Alias of the code-generated [ttsPlaybackStateNotifierProvider] so the
/// provider name stays stable even if the notifier is renamed.
final ttsPlaybackStateProvider = ttsPlaybackStateNotifierProvider;
