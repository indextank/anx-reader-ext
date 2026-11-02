import 'dart:typed_data';

/// Typed configuration for the StepAudio (StepFun) TTS service.
///
/// Values are persisted through the generic online TTS config storage as a
/// `Map<String, dynamic>`; this class gives the adapter typed access.
class StepAudioTtsConfig {
  final String url;
  final String apiKey;
  final String model;
  final String voice;
  final String responseFormat;
  final String textNormalization;
  final int timeoutSeconds;

  const StepAudioTtsConfig({
    required this.url,
    required this.apiKey,
    required this.model,
    required this.voice,
    required this.responseFormat,
    required this.textNormalization,
    required this.timeoutSeconds,
  });

  static const String defaultUrl = 'https://api.stepfun.com/v1/audio/speech';
  static const String defaultModel = 'step-tts-2';
  static const String defaultVoice = 'cixingnansheng';
  static const String defaultResponseFormat = 'mp3';
  static const int defaultTimeoutSeconds = 30;

  /// Doc default is `standard` (lower latency); `enhanced` is recommended by
  /// the docs for long-form narration and number/unit handling, which is
  /// what whole-book reading is, so it is the default here.
  static const String defaultTextNormalization = 'enhanced';
  static const List<String> textNormalizationOptions = ['standard', 'enhanced'];

  /// Models documented by StepFun for `/v1/audio/speech`.
  static const List<String> modelOptions = [
    'step-tts-2',
    'step-tts-mini',
    'stepaudio-2.5-tts',
    'stepaudio-3-tts',
  ];

  /// Audio formats documented by StepFun that the built-in player supports.
  static const List<String> responseFormatOptions = ['mp3', 'wav'];

  factory StepAudioTtsConfig.fromMap(Map<String, dynamic> map) {
    final timeout =
        int.tryParse(map['timeout']?.toString() ?? '') ?? defaultTimeoutSeconds;
    return StepAudioTtsConfig(
      url: normalizeStepAudioUrl(map['url']?.toString() ?? ''),
      apiKey: map['key']?.toString() ?? '',
      model: map['model']?.toString().trim().isNotEmpty == true
          ? map['model'].toString().trim()
          : defaultModel,
      voice: map['voice']?.toString().trim().isNotEmpty == true
          ? map['voice'].toString().trim()
          : defaultVoice,
      responseFormat:
          map['responseFormat']?.toString().trim().isNotEmpty == true
              ? map['responseFormat'].toString().trim()
              : defaultResponseFormat,
      textNormalization: textNormalizationOptions
              .contains(map['textNormalization']?.toString().trim())
          ? map['textNormalization'].toString().trim()
          : defaultTextNormalization,
      timeoutSeconds: timeout > 0 ? timeout : defaultTimeoutSeconds,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'key': apiKey,
        'model': model,
        'voice': voice,
        'responseFormat': responseFormat,
        'textNormalization': textNormalization,
        'timeout': timeoutSeconds,
      };
}

/// Normalize a user-supplied StepAudio endpoint.
///
/// Accepts either the full endpoint (`https://api.stepfun.com/v1/audio/speech`)
/// or a base URL (`https://api.stepfun.com/v1`, optionally with trailing
/// slashes) and always returns the full endpoint.
String normalizeStepAudioUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return StepAudioTtsConfig.defaultUrl;
  if (url.endsWith('/audio/speech')) return url;
  return '${url.replaceAll(RegExp(r'/+$'), '')}/audio/speech';
}

/// Build the HTTP headers for a StepAudio speech request.
///
/// StepFun authenticates with `Authorization: Bearer <API key>`.
Map<String, String> buildStepAudioHeaders(String apiKey) => {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

/// Clamp the reader rate to the `speed` range documented by StepFun (0.5–2.0).
double clampStepAudioSpeed(double rate) => rate.clamp(0.5, 2.0);

/// Build the StepAudio `/v1/audio/speech` request body.
///
/// Only documented fields are emitted. `input` max length is 1000 characters
/// per the official docs, so longer texts must be split upstream.
Map<String, dynamic> buildStepAudioRequestBody({
  required String model,
  required String input,
  required String voice,
  required String responseFormat,
  required double speed,
  String textNormalization = StepAudioTtsConfig.defaultTextNormalization,
}) =>
    {
      'model': model,
      'input': input,
      'voice': voice,
      'response_format': responseFormat,
      'speed': speed,
      'text_normalization': textNormalization,
    };

/// Turn a StepAudio HTTP response into raw audio bytes.
///
/// The API returns the audio file as a binary stream on success; an empty body
/// is treated as an empty result so the caller can surface it as silence.
/// Non-200 responses raise an [Exception] with a readable message.
Uint8List parseStepAudioResponse({
  required int statusCode,
  required Uint8List bodyBytes,
  required String bodyText,
}) {
  if (statusCode == 200) {
    return bodyBytes;
  }

  final reason = _describeStepAudioStatus(statusCode);
  final detail = bodyText.trim();
  if (detail.isEmpty) {
    throw Exception('StepAudio TTS request failed (HTTP $statusCode): $reason');
  }
  throw Exception(
      'StepAudio TTS request failed (HTTP $statusCode): $reason - ${_truncate(detail)}');
}

String _describeStepAudioStatus(int statusCode) {
  switch (statusCode) {
    case 401:
    case 403:
      return 'authentication failed, please check your API key';
    case 429:
      return 'rate limited, please retry later';
    case 400:
      return 'invalid request parameters';
    default:
      return statusCode >= 500
          ? 'StepAudio server error'
          : 'unexpected response';
  }
}

String _truncate(String text, [int max = 200]) =>
    text.length <= max ? text : text.substring(0, max);
