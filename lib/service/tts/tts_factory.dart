import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the active [BaseTts] engine instance and performs engine switching.
class TtsFactory {
  static final TtsFactory _instance = TtsFactory._internal();

  factory TtsFactory() {
    return _instance;
  }

  TtsFactory._internal();

  BaseTts? _currentTts;

  BaseTts get current {
    _currentTts ??= createTts();
    return _currentTts!;
  }

  BaseTts createTts() {
    final service = getTtsService(Prefs().ttsService);
    return service == TtsService.system ? SystemTts() : OnlineTts();
  }

  /// Stops and releases the current engine, persists [serviceId] and creates
  /// the engine for the new service.
  Future<void> switchTtsType(String serviceId) async {
    if (Prefs().ttsService == serviceId) return;

    final previous = _currentTts;
    if (previous != null) {
      // Stop (not dispose): both engines are app-lifetime singletons that can
      // be re-initialized; stop releases the audio output and cancels all
      // in-flight sessions.
      await previous.stop();
      _currentTts = null;
    }

    Prefs().ttsService = serviceId;
    _currentTts = createTts();
  }

  Future<void> dispose() async {
    final previous = _currentTts;
    _currentTts = null;
    if (previous != null) {
      await previous.stop();
      await previous.dispose();
    }
  }

  ValueNotifier<TtsStateEnum> get ttsStateNotifier {
    return current.ttsStateNotifier;
  }
}
