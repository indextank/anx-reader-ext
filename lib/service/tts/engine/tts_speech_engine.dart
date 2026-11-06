import 'dart:typed_data';

import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

/// Immutable TTS settings shared by every engine adapter.
class TtsSpeechConfig {
  const TtsSpeechConfig({
    required this.rate,
    required this.pitch,
    required this.volume,
    this.voice,
  });

  /// UI rate in flutter_tts units (0.5 is normal speed, 1.0 is 2x).
  final double rate;

  /// UI pitch in flutter_tts units (1.0 is normal).
  final double pitch;

  /// Output volume in the 0..1 range.
  final double volume;

  /// Engine specific voice id, when the engine supports explicit voices.
  final String? voice;

  TtsSpeechConfig copyWith({
    double? rate,
    double? pitch,
    double? volume,
    String? voice,
  }) {
    return TtsSpeechConfig(
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      voice: voice ?? this.voice,
    );
  }

  @override
  String toString() =>
      'TtsSpeechConfig(rate: $rate, pitch: $pitch, volume: $volume, '
      'voice: $voice)';
}

/// Typed failure raised by synthesis engine adapters. The pipeline converts
/// it into a [TtsPlaybackError] carrying the engine, stage and context, and
/// uses [isOversized] to split an over-limit request before retrying instead
/// of silently dropping a paragraph (the Aliyun skip root cause).
class TtsEngineSynthesisException implements Exception {
  const TtsEngineSynthesisException({
    required this.engine,
    required this.message,
    this.cause,
    this.isOversized = false,
    this.isRateLimited = false,
    this.context = const <String, String>{},
  });

  final TtsEngineKind engine;
  final String message;
  final Object? cause;

  /// True when the failure is caused by the input exceeding the engine limit
  /// (HTTP 400 / documented character cap), so the pipeline can split.
  final bool isOversized;

  /// True when the engine/gateway rejected the request because too many
  /// requests arrived at once (`Gateway:TOO_MANY_REQUESTS`, Aliyun status
  /// `40000005`, HTTP 429). The playback pipeline then retries with an
  /// exponential backoff instead of the short generic retry delay: a tight
  /// 120/240 ms retry loop just burns the remaining quota and is exactly the
  /// real-device 1.2-1.4 s chapter-start gap this flag fixes.
  final bool isRateLimited;

  final Map<String, String> context;

  @override
  String toString() => 'TtsEngineSynthesisException(${engine.name}: $message, '
      'oversized: $isOversized, rateLimited: $isRateLimited, '
      'context: $context)';
}

/// One synthesis request for a cloud engine.
class TtsSynthesisRequest {
  const TtsSynthesisRequest({
    required this.text,
    required this.config,
    required this.engine,
    this.utteranceId,
  });

  final String text;
  final TtsSpeechConfig config;
  final TtsEngineKind engine;
  final String? utteranceId;

  @override
  String toString() =>
      'TtsSynthesisRequest(${engine.name}, ${text.length} chars, '
      'utterance: $utteranceId)';
}

/// Capabilities that the pipeline branches on. Explicit instead of probing
/// engine internals with `is` checks or `dynamic` calls.
class TtsEngineCapabilities {
  const TtsEngineCapabilities({
    required this.engine,
    required this.supportsNativePause,
    required this.appliesRateOnServer,
    required this.reportsCharacterProgress,
    required this.maxRequestChars,
    this.needsOutputWarmup = false,
  });

  final TtsEngineKind engine;

  /// Whether the engine can pause in place (system TTS on Windows/iOS/macOS/
  /// Android >= 26 can; cloud engines pause the audio player).
  final bool supportsNativePause;

  /// Whether the rate argument changes the generated audio (cloud engines).
  /// When false the pipeline applies the rate through the audio player.
  final bool appliesRateOnServer;

  /// Whether the engine reports character level progress. When false the
  /// pipeline falls back to sentence-start anchors calibrated to word
  /// boundaries.
  final bool reportsCharacterProgress;

  /// Maximum characters accepted in one request.
  final int maxRequestChars;

  /// Whether the audio output should be warmed up before the first request
  /// (Windows MediaFoundation clips the head of a cold audio stream).
  final bool needsOutputWarmup;

  TtsEngineCapabilities copyWith({
    bool? supportsNativePause,
    bool? appliesRateOnServer,
    bool? reportsCharacterProgress,
    int? maxRequestChars,
    bool? needsOutputWarmup,
  }) {
    return TtsEngineCapabilities(
      engine: engine,
      supportsNativePause: supportsNativePause ?? this.supportsNativePause,
      appliesRateOnServer: appliesRateOnServer ?? this.appliesRateOnServer,
      reportsCharacterProgress:
          reportsCharacterProgress ?? this.reportsCharacterProgress,
      maxRequestChars: maxRequestChars ?? this.maxRequestChars,
      needsOutputWarmup: needsOutputWarmup ?? this.needsOutputWarmup,
    );
  }

  @override
  String toString() => 'TtsEngineCapabilities(${engine.name}, nativePause: '
      '$supportsNativePause, serverRate: $appliesRateOnServer, maxChars: '
      '$maxRequestChars)';
}

/// Cloud/offline synthesis engine adapter (Aliyun, MiMo, StepAudio, Azure,
/// OpenAI, fake engines in tests).
abstract interface class TtsSynthesisEngine {
  TtsEngineKind get kind;
  String get engineId;
  TtsEngineCapabilities get capabilities;

  Future<Uint8List> synthesize(TtsSynthesisRequest request);

  Future<List<TtsVoice>> voices();

  Future<void> dispose();
}

/// Events emitted by the native (system) speech engine. Kept typed so stale
/// completion callbacks can be distinguished from the active generation.
sealed class TtsNativeEvent {
  const TtsNativeEvent({required this.generation});

  final int generation;
}

final class TtsNativeStarted extends TtsNativeEvent {
  const TtsNativeStarted({required super.generation});
}

final class TtsNativeCompleted extends TtsNativeEvent {
  const TtsNativeCompleted({required super.generation});
}

final class TtsNativeCancelled extends TtsNativeEvent {
  const TtsNativeCancelled({required super.generation});
}

final class TtsNativePaused extends TtsNativeEvent {
  const TtsNativePaused({required super.generation});
}

final class TtsNativeContinued extends TtsNativeEvent {
  const TtsNativeContinued({required super.generation});
}

final class TtsNativeFailed extends TtsNativeEvent {
  const TtsNativeFailed({
    required super.generation,
    required this.message,
    this.stage = TtsStageIdForNative.initialize,
  });

  final String message;
  final TtsStageIdForNative stage;
}

/// Stage ids used by native engine failures. Kept as an enum to avoid raw
/// strings crossing the adapter boundary.
enum TtsStageIdForNative { initialize, speak, pause, resume, stop, query }

/// System (platform) speech engine adapter. Production implementation wraps
/// `flutter_tts`; tests inject a controllable fake.
abstract interface class TtsNativeSpeechEngine {
  TtsEngineKind get kind;
  TtsEngineCapabilities get capabilities;

  Future<void> initialize({TtsSpeechConfig? config});
  Future<void> configure(TtsSpeechConfig config);

  /// Speaks [text] and completes when the engine reports completion.
  ///
  /// Implementations must reject a new speak while one is in flight (or
  /// cancel-then-speak explicitly), so the pipeline controls sequencing.
  Future<void> speak(String text);

  /// Native pause. Engines without native pause throw [UnsupportedError]; the
  /// pipeline then simulates pause by stopping and re-synthesizing from the
  /// word-boundary cursor.
  Future<void> pause();

  /// Native resume after [pause].
  Future<void> resume();

  Future<void> stop();

  Future<List<TtsVoice>> voices();

  Stream<TtsNativeEvent> get events;

  int get generation;

  Future<void> dispose();
}
