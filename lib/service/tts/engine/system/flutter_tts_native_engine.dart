import 'dart:async';

import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Typed failure raised by [FlutterTtsNativeEngine].
///
/// The pipeline converts it into the matching typed playback error, so no raw
/// `PlatformException`/`MissingPluginException` ever reaches the UI.
class TtsNativeEngineException implements Exception {
  const TtsNativeEngineException({
    required this.stage,
    required this.message,
    this.cause,
  });

  final TtsStageIdForNative stage;
  final String message;
  final Object? cause;

  @override
  String toString() => 'TtsNativeEngineException(${stage.name}: $message)';
}

/// System (platform) speech engine backed by `package:flutter_tts`.
///
/// Platform nuances are encapsulated here so the playback pipeline stays
/// platform agnostic:
/// - Windows (this repo vendors the Anxcye/flutter_tts fork, SAPI back end):
///   [pause] calls the plugin's native `ISpVoice::Pause`; [resume] calls
///   `speak('')`, which the plugin maps to its `continuePlay()` path. The
///   original speak request keeps waiting, so the resumed utterance finishes
///   normally and its completion is delivered for the same generation.
/// - iOS/macOS: `AVSpeechSynthesizer.pauseSpeaking`; resuming also goes
///   through `speak`, which tells the plugin to `continueSpeaking()`.
/// - Android: queue mode 1 (add) is kept for compatibility with the old
///   behaviour; `pause` stops and remembers the remaining text, a later
///   `speak(<same text>)` continues it, so [resume] re-sends the last text.
/// - Linux/web: the engine is unavailable; every call fails with a typed
///   [TtsNativeEngineException] and the pipeline degrades gracefully (the
///   production [SystemTts] short-circuits these platforms).
class FlutterTtsNativeEngine implements TtsNativeSpeechEngine {
  FlutterTtsNativeEngine();

  /// Android's `TextToSpeech.getMaxSpeechInputLength()` is 4000 on every
  /// supported version (the plugin exposes the same value); kept as the
  /// conservative request size cap for the system engine.
  static const int _maxRequestChars = 4000;

  final StreamController<TtsNativeEvent> _events =
      StreamController<TtsNativeEvent>.broadcast();

  FlutterTts? _client;
  List<TtsVoice>? _voicesCache;

  int _generation = 0;
  int _configuredVolume = -1;
  int _configuredPitch = -1;
  int _configuredRate = -1;
  String? _configuredVoice;

  Completer<void>? _pendingSpeak;
  bool _startedCurrentGeneration = false;
  bool _paused = false;
  bool _initialized = false;
  bool _disposed = false;
  String? _lastSpokenText;

  /// Set when [speak] deliberately stops the plugin to leave a stale paused
  /// state: the resulting `speak.onCancel` callback belongs to that reset, not
  /// to the new utterance.
  bool _ignoreNextCancel = false;

  late final _NativePlatform _platform = _detectPlatform();

  FlutterTts get _flutterTts => _client ??= FlutterTts();

  static _NativePlatform _detectPlatform() {
    if (kIsWeb) return _NativePlatform.web;
    try {
      switch (AnxPlatform.type) {
        case AnxPlatformEnum.android:
          return _NativePlatform.android;
        case AnxPlatformEnum.ios:
          return _NativePlatform.ios;
        case AnxPlatformEnum.macos:
          return _NativePlatform.macos;
        case AnxPlatformEnum.windows:
          return _NativePlatform.windows;
        case AnxPlatformEnum.linux:
          return _NativePlatform.linux;
        case AnxPlatformEnum.ohos:
          return _NativePlatform.other;
      }
    } catch (_) {
      // Some embedders do not expose dart:io Platform; treat as unsupported
      // instead of crashing app startup.
      return _NativePlatform.other;
    }
  }

  bool get _unavailable =>
      _platform == _NativePlatform.web ||
      _platform == _NativePlatform.linux ||
      _platform == _NativePlatform.other;

  bool get _isAndroid => _platform == _NativePlatform.android;

  // ============ TtsNativeSpeechEngine ============

  @override
  TtsEngineKind get kind => TtsEngineKind.system;

  @override
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: TtsEngineKind.system,
        // Windows/iOS/macOS pause the audio in place; Android pauses through
        // the plugin's stop + replay-remaining-text implementation. Linux and
        // web have no system engine at all.
        supportsNativePause: !_unavailable,
        appliesRateOnServer: false,
        // flutter_tts reports word boundaries, not character-level progress;
        // the pipeline uses sentence-start anchors calibrated to word
        // boundaries instead.
        reportsCharacterProgress: false,
        maxRequestChars: _maxRequestChars,
        needsOutputWarmup: false,
      );

  @override
  Stream<TtsNativeEvent> get events => _events.stream;

  @override
  int get generation => _generation;

  @override
  Future<void> initialize({TtsSpeechConfig? config}) async {
    if (_disposed) {
      throw _fail(TtsStageIdForNative.initialize,
          'the system TTS engine was disposed and cannot be re-initialized');
    }
    if (_unavailable) {
      throw _fail(TtsStageIdForNative.initialize,
          'system TTS is not supported on this platform');
    }
    if (!_initialized) {
      _installHandlers();
      try {
        // The plugin reports completion through handlers on every platform;
        // awaiting the platform call keeps the old (awaitSpeakCompletion)
        // contract for adapters that still expect it.
        await _flutterTts.awaitSpeakCompletion(true);
        if (_isAndroid) {
          // Old Android behaviour kept for queue mode 1 + synthesize
          // completion; encapsulated here so the pipeline is unaffected.
          await _flutterTts.awaitSynthCompletion(true);
          await _flutterTts.setQueueMode(1);
        }
      } on MissingPluginException catch (error) {
        throw _fail(TtsStageIdForNative.initialize,
            'flutter_tts plugin is not available on this platform', error);
      } on PlatformException catch (error) {
        throw _fail(TtsStageIdForNative.initialize,
            'flutter_tts initialization failed: ${error.message}', error);
      }
      _initialized = true;
    }
    if (config != null) {
      await configure(config);
    }
  }

  @override
  Future<void> configure(TtsSpeechConfig config) async {
    _ensureUsable(TtsStageIdForNative.initialize);
    final volume = config.volume.clamp(0.0, 1.0).toDouble();
    final pitch = config.pitch.clamp(0.5, 2.0).toDouble();
    // The app's UI rate uses flutter_tts units (0.5 is normal speed, 1.0 is
    // double speed) and the vendored plugin accepts the full 0..2 range.
    final rate = config.rate.isFinite ? config.rate.clamp(0.0, 2.0) : 0.6;
    try {
      // Only push changed values: configure() runs before every utterance and
      // the rate change must stay cheap on the audio thread.
      final volumeKey = (volume * 100).round();
      if (volumeKey != _configuredVolume) {
        await _flutterTts.setVolume(volume);
        _configuredVolume = volumeKey;
      }
      final pitchKey = (pitch * 100).round();
      if (pitchKey != _configuredPitch) {
        await _flutterTts.setPitch(pitch);
        _configuredPitch = pitchKey;
      }
      final rateKey = (rate * 1000).round();
      if (rateKey != _configuredRate) {
        await _flutterTts.setSpeechRate(rate);
        _configuredRate = rateKey;
      }
      if (config.voice != null && config.voice != _configuredVoice) {
        final voice = config.voice!;
        if (voice.isEmpty) {
          // Back to the platform default voice after a preview override.
          if (_configuredVoice != null && _configuredVoice!.isNotEmpty) {
            try {
              await _flutterTts.clearVoice();
            } catch (_) {
              // Not every platform implements clearVoice; the default voice
              // remains active, so this is best effort.
            }
          }
          _configuredVoice = '';
        } else {
          await _applyVoice(voice);
        }
      }
    } on MissingPluginException catch (error) {
      throw _fail(TtsStageIdForNative.initialize,
          'flutter_tts plugin is not available on this platform', error);
    } on PlatformException catch (error) {
      throw _fail(TtsStageIdForNative.initialize,
          'flutter_tts configure failed: ${error.message}', error);
    }
  }

  @override
  Future<void> speak(String text) async {
    _ensureUsable(TtsStageIdForNative.speak);
    if (_pendingSpeak != null) {
      throw _fail(
          TtsStageIdForNative.speak,
          'a speak request is already in flight; the pipeline must sequence '
          'requests');
    }
    if (_paused) {
      // A *new* utterance must not be mistaken for a "continue" request by the
      // plugin: clear the native pause state first (Windows/iOS ignore the new
      // text while paused).
      _paused = false;
      _ignoreNextCancel = true;
      try {
        await _flutterTts.stop();
      } on MissingPluginException catch (error) {
        throw _fail(TtsStageIdForNative.stop,
            'flutter_tts plugin is not available on this platform', error);
      }
    }
    final generation = ++_generation;
    _lastSpokenText = text;
    _startedCurrentGeneration = false;
    final completer = Completer<void>();
    _pendingSpeak = completer;
    unawaited(_dispatchSpeak(text, generation, completer));
    return completer.future;
  }

  @override
  Future<void> pause() async {
    _ensureUsable(TtsStageIdForNative.pause);
    if (_paused) return;
    _paused = true;
    try {
      await _flutterTts.pause();
    } on MissingPluginException catch (error) {
      _paused = false;
      throw _fail(TtsStageIdForNative.pause,
          'flutter_tts plugin is not available on this platform', error);
    } on PlatformException catch (error) {
      _paused = false;
      throw _fail(TtsStageIdForNative.pause,
          'flutter_tts pause failed: ${error.message}', error);
    }
    _emit(TtsNativePaused(generation: _generation));
  }

  @override
  Future<void> resume() async {
    _ensureUsable(TtsStageIdForNative.resume);
    if (!_paused) return;
    _paused = false;
    // Android continues the native utterance by re-sending the original text
    // (the plugin trims it to its remembered remaining offset); Windows/
    // iOS/macOS ignore the text and simply continue the paused utterance.
    final text = _isAndroid ? (_lastSpokenText ?? '') : '';
    unawaited(_dispatchResume(text));
    _emit(TtsNativeContinued(generation: _generation));
  }

  @override
  Future<void> stop() async {
    _paused = false;
    _startedCurrentGeneration = false;
    _generation++;
    final pending = _pendingSpeak;
    _pendingSpeak = null;
    _emit(TtsNativeCancelled(generation: _generation));
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    if (!_initialized || _unavailable || _disposed) return;
    try {
      await _flutterTts.stop();
    } on MissingPluginException {
      // Engine already gone; stopping is a no-op.
    } on PlatformException {
      // Stopping is best effort: the pipeline already cancelled its session.
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    _ensureUsable(TtsStageIdForNative.query);
    final cached = _voicesCache;
    if (cached != null) return cached;
    final raw =
        await _guard(TtsStageIdForNative.query, () => _flutterTts.getVoices);
    final mapped = <TtsVoice>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = <String, dynamic>{};
        for (final mapEntry in entry.entries) {
          final key = mapEntry.key;
          if (key is! String) continue;
          map[key] = mapEntry.value;
        }
        final name = _stringOf(map['name']);
        final identifier = _stringOf(map['identifier']);
        final locale = _stringOf(map['locale']).replaceAll('_', '-');
        final gender = _stringOf(map['gender']);
        if (name.isEmpty && identifier.isEmpty) continue;
        mapped.add(TtsVoice(
          shortName: name.isNotEmpty ? name : identifier,
          name: name.isNotEmpty ? name : identifier,
          locale: locale,
          gender: gender.toLowerCase(),
          rawData: map,
        ));
      }
    }
    final result = List<TtsVoice>.unmodifiable(mapped);
    _voicesCache = result;
    return result;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _pendingSpeak;
    _pendingSpeak = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    try {
      await _flutterTts.stop();
    } catch (_) {
      // Best effort during shutdown.
    }
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  // ============ Internal ============

  void _installHandlers() {
    final client = _flutterTts;
    client.setStartHandler(_handleStart);
    client.setCompletionHandler(_handleCompletion);
    client.setCancelHandler(_handleCancel);
    client.setPauseHandler(_handlePause);
    client.setContinueHandler(_handleContinue);
    client.setErrorHandler(_handleError);
  }

  Future<void> _dispatchSpeak(
    String text,
    int generation,
    Completer<void> completer,
  ) async {
    try {
      // The platform call's own future is not the completion signal on every
      // platform (Android queue mode 1 resolves it immediately, iOS replaces
      // the stored result when the utterance is resumed), so state is driven
      // by the typed handlers below. Errors still surface here.
      await _flutterTts.speak(text);
    } on MissingPluginException catch (error) {
      _failPending(generation, completer,
          'flutter_tts plugin is not available on this platform', error);
    } on PlatformException catch (error) {
      _failPending(generation, completer,
          'flutter_tts speak failed: ${error.message}', error);
    } catch (error) {
      _failPending(
          generation, completer, 'flutter_tts speak failed: $error', error);
    }
  }

  Future<void> _dispatchResume(String text) async {
    try {
      await _flutterTts.speak(text);
    } on MissingPluginException catch (error) {
      _failCurrent(TtsStageIdForNative.resume,
          'flutter_tts plugin is not available on this platform', error);
    } on PlatformException catch (error) {
      _failCurrent(TtsStageIdForNative.resume,
          'flutter_tts resume failed: ${error.message}', error);
    } catch (error) {
      _failCurrent(TtsStageIdForNative.resume,
          'flutter_tts resume failed: $error', error);
    }
  }

  void _handleStart() {
    if (_disposed || _pendingSpeak == null || _startedCurrentGeneration) return;
    _ignoreNextCancel = false;
    _startedCurrentGeneration = true;
    _emit(TtsNativeStarted(generation: _generation));
  }

  void _handleCompletion() {
    if (_disposed) return;
    final pending = _pendingSpeak;
    if (pending == null || pending.isCompleted) return;
    if (!_startedCurrentGeneration) {
      // Completion of a previous generation that arrived after a stop/new
      // speak: never let it settle the current request (and never report it as
      // a failure of the current one).
      return;
    }
    _startedCurrentGeneration = false;
    _pendingSpeak = null;
    _emit(TtsNativeCompleted(generation: _generation));
    pending.complete();
  }

  void _handleCancel() {
    if (_disposed) return;
    if (_ignoreNextCancel) {
      // Cancel caused by the deliberate pause-state reset inside speak().
      _ignoreNextCancel = false;
      return;
    }
    if (_paused) {
      // Pause stops the native utterance but the pipeline still awaits the
      // resumed completion, so the pending request must stay pending.
      _emit(TtsNativeCancelled(generation: _generation));
      return;
    }
    final pending = _pendingSpeak;
    _startedCurrentGeneration = false;
    _pendingSpeak = null;
    _emit(TtsNativeCancelled(generation: _generation));
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  void _handlePause() {
    if (_disposed || !_paused) return;
    _emit(TtsNativePaused(generation: _generation));
  }

  void _handleContinue() {
    if (_disposed || _paused) return;
    _emit(TtsNativeContinued(generation: _generation));
  }

  void _handleError(dynamic message) {
    if (_disposed) return;
    final text = _messageOf(message);
    _failCurrent(TtsStageIdForNative.speak, text, message);
  }

  void _failPending(
    int generation,
    Completer<void> completer,
    String message,
    Object cause,
  ) {
    if (_disposed || generation != _generation || completer.isCompleted) {
      return;
    }
    _pendingSpeak = null;
    _startedCurrentGeneration = false;
    _emit(TtsNativeFailed(
      generation: generation,
      message: message,
      stage: TtsStageIdForNative.speak,
    ));
    completer.completeError(TtsNativeEngineException(
      stage: TtsStageIdForNative.speak,
      message: message,
      cause: cause,
    ));
  }

  void _failCurrent(
    TtsStageIdForNative stage,
    String message,
    Object? cause,
  ) {
    if (_disposed) return;
    final pending = _pendingSpeak;
    _pendingSpeak = null;
    _startedCurrentGeneration = false;
    _emit(TtsNativeFailed(
      generation: _generation,
      message: message,
      stage: stage,
    ));
    if (pending != null && !pending.isCompleted) {
      pending.completeError(TtsNativeEngineException(
        stage: stage,
        message: message,
        cause: cause,
      ));
    }
  }

  Future<T> _guard<T>(
    TtsStageIdForNative stage,
    Future<T> Function() call,
  ) async {
    try {
      return await call();
    } on MissingPluginException catch (error) {
      throw _fail(
          stage, 'flutter_tts plugin is not available on this platform', error);
    } on PlatformException catch (error) {
      throw _fail(
          stage, 'flutter_tts ${stage.name} failed: ${error.message}', error);
    }
  }

  TtsNativeEngineException _fail(
    TtsStageIdForNative stage,
    String message, [
    Object? cause,
  ]) {
    _emit(TtsNativeFailed(
      generation: _generation,
      message: message,
      stage: stage,
    ));
    return TtsNativeEngineException(
      stage: stage,
      message: message,
      cause: cause,
    );
  }

  void _ensureUsable(TtsStageIdForNative stage) {
    if (_disposed) {
      throw TtsNativeEngineException(
        stage: stage,
        message: 'the system TTS engine was disposed',
      );
    }
    if (_unavailable) {
      throw TtsNativeEngineException(
        stage: stage,
        message: 'system TTS is not supported on this platform',
      );
    }
  }

  Future<void> _applyVoice(String? voiceId) async {
    if (voiceId == null || voiceId.isEmpty) return;
    final voices = await this.voices();
    for (final voice in voices) {
      if (voice.shortName != voiceId && voice.name != voiceId) continue;
      try {
        await _flutterTts.setVoice(<String, String>{
          'name': voice.name,
          'locale': voice.locale.replaceAll('-', '_'),
        });
        _configuredVoice = voiceId;
      } on MissingPluginException {
        // Voice selection is best effort; the default voice keeps working.
      } on PlatformException {
        // Same: never fail playback because a voice id is unknown.
      }
      return;
    }
  }

  void _emit(TtsNativeEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  static String _stringOf(Object? value) => value is String ? value : '';

  static String _messageOf(Object? message) {
    if (message is String) return message;
    if (message is Object) return '$message';
    return 'unknown native TTS error';
  }
}

enum _NativePlatform { android, ios, macos, windows, linux, other, web }
