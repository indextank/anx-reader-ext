import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config/service_provider.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:flutter/widgets.dart';

// Re-export ConfigItem for convenience
export 'package:anx_reader/service/config/config_item.dart';

// Forward declaration to avoid circular dependency
// The actual TtsService enum is defined in tts_service.dart
// ignore: unused_element
abstract class _TtsService {}

/// Base class for all TTS service providers.
///
/// Subclasses must implement:
/// - [service]: The TTS service enum value.
/// - [getLabel]: The display label.
/// - For online TTS services:
///   - [speak]: Generate speech audio from text.
///   - [getVoices]: Get available voices.
///   - [getConfigItems]: Configuration items.
///   - [getConfig] / [saveConfig]: Configuration management.
abstract class TtsServiceProvider extends ServiceProvider<dynamic> {
  String get serviceId => service.toString().split('.').last;

  /// The display label for this service.
  @override
  String getLabel(BuildContext context);

  /// Maximum text length (in characters) sent to [speak] in a single
  /// request. The playback pipeline splits longer sentences before
  /// requesting audio, so no text is dropped when an engine rejects
  /// oversized input. Engines with a documented limit override this.
  int get maxRequestChars => 800;

  /// Human-readable evidence for [maxRequestChars]: the documentation
  /// sentence (or the explicit "no documented limit" fallback) the cap comes
  /// from. Surfaced in diagnostics so a split request can be explained
  /// without reading the engine sources.
  String get documentedRequestLimitNote =>
      'No documented request limit for $serviceId; $maxRequestChars '
      'characters is a conservative safety cap';

  /// Whether the engine can pause in place. Cloud engines only pause the
  /// playback of their audio output, so they all report false; the system
  /// engine reports its capability through `TtsNativeSpeechEngine` instead.
  bool get supportsNativePause => false;

  /// Whether the engine reports character-level playback progress. Cloud
  /// engines do not, so the pipeline falls back to sentence-start anchors
  /// calibrated to word boundaries.
  bool get reportsCharacterProgress => false;

  /// Whether the engine applies [speak]'s rate argument server-side.
  /// Engines without a documented speed parameter must return false; the
  /// playback pipeline then applies the rate via player playback speed so
  /// the UI slider still works and takes effect immediately.
  bool get supportsRateParameter => true;

  /// Maximum number of synthesis requests this provider accepts concurrently.
  ///
  /// The playback pipeline deliberately issues several requests in parallel
  /// (cold-start warm-up plus a lookahead prefetch window), so without an
  /// adapter-side bound a new chapter can produce 5-6 simultaneous requests.
  /// Aliyun's gateway answered exactly that burst with
  /// `400 {"status":40000005,"message":"Gateway:TOO_MANY_REQUESTS:Too many
  /// requests!"}` on the real device.
  ///
  /// The shared default of 2 is a conservative safety cap: it matches the
  /// concurrency the round-2 test harness already models for Aliyun
  /// (`Round2EngineProfile.aliyun.maxParallelRequests = 2`) and no engine has a
  /// documented allowance for more. Providers that can tolerate more may
  /// override it (never above their documented quota).
  int get maxConcurrentSynthesisRequests => 2;

  /// Minimum spacing between two synthesis request *starts*.
  ///
  /// Zero means "no extra spacing": the concurrency bound alone is enough for
  /// providers without a known burst/QPS rejection. Providers whose gateway
  /// enforces a QPS window override this; Aliyun rejects bursts with
  /// `TOO_MANY_REQUESTS` and spaces request starts by 250 ms (at most four
  /// starts per second, well inside the observed gateway tolerance).
  Duration get minSynthesisRequestInterval => Duration.zero;

  /// Generate speech audio from text.
  /// Only required for online TTS services.
  /// System TTS doesn't use this method.
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    throw UnimplementedError('speak() not implemented for $service');
  }

  /// Get available voices for this TTS service.
  /// Returns empty list for system TTS (handled separately).
  Future<List<TtsVoice>> getVoices() async {
    return [];
  }

  /// Convert voice data from API response to TtsVoice model.
  /// Only needed for online TTS services.
  TtsVoice convertVoiceModel(dynamic voiceData) {
    throw UnimplementedError(
        'convertVoiceModel() not implemented for $service');
  }

  /// Get the currently selected voice for this service.
  String getSelectedVoice() {
    return Prefs().getTtsVoiceModel(serviceId);
  }

  /// Persist the selected voice for this service.
  void setSelectedVoice(String voice) {
    Prefs().setTtsVoiceModel(serviceId, voice);
  }

  /// Resolve the voice to use, optionally overriding the saved selection.
  String resolveVoice(String? voiceOverride) {
    if (voiceOverride != null && voiceOverride.isNotEmpty) {
      return voiceOverride;
    }
    final selected = getSelectedVoice();
    if (selected.isEmpty) {
      throw Exception('No voice selected for $service');
    }
    return selected;
  }
}

/// Typed rate-limit failure raised by a [TtsServiceProvider] when the engine
/// or the gateway in front of it rejects a request burst.
///
/// Providers throw this instead of a generic [Exception] so the adapter layer
/// can map it to `TtsEngineSynthesisException(isRateLimited: true)` and the
/// playback pipeline can use its exponential retry backoff instead of the
/// short generic one. The message still carries the raw response for logs and
/// diagnostics.
class TtsRateLimitException implements Exception {
  const TtsRateLimitException({
    required this.message,
    this.statusCode,
    this.body,
    this.retryAfter,
    this.cause,
  });

  final String message;

  /// HTTP status of the rejected response (400 for the Aliyun gateway
  /// `40000005`, 429 for a standard rate-limit response).
  final int? statusCode;

  /// Raw response body, kept for diagnostics.
  final String? body;

  /// Server-provided `Retry-After` hint, when present.
  final Duration? retryAfter;

  final Object? cause;

  @override
  String toString() => 'TtsRateLimitException($message)';
}
