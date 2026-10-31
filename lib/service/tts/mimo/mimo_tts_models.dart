import 'dart:convert';
import 'dart:typed_data';

/// Typed configuration for the MiMo (Xiaomi) TTS service.
///
/// Values are persisted through the generic online TTS config storage as a
/// `Map<String, dynamic>`; this class gives the adapter typed access.
class MimoTtsConfig {
  final String url;
  final String apiKey;
  final String model;
  final String voice;
  final String format;
  final String instruction;
  final int timeoutSeconds;

  const MimoTtsConfig({
    required this.url,
    required this.apiKey,
    required this.model,
    required this.voice,
    required this.format,
    required this.instruction,
    required this.timeoutSeconds,
  });

  static const String defaultUrl =
      'https://api.xiaomimimo.com/v1/chat/completions';
  static const String defaultModel = 'mimo-v2.5-tts';
  static const String defaultVoice = 'mimo_default';
  static const String defaultFormat = 'mp3';
  static const int defaultTimeoutSeconds = 30;

  /// Models documented by MiMo for the audio TTS endpoint.
  static const List<String> modelOptions = [
    'mimo-v2.5-tts',
    'mimo-v2.5-tts-voicedesign',
    'mimo-v2.5-tts-voiceclone',
  ];

  /// Audio formats documented by MiMo that the built-in player supports.
  static const List<String> formatOptions = ['mp3', 'wav'];

  factory MimoTtsConfig.fromMap(Map<String, dynamic> map) {
    final timeout =
        int.tryParse(map['timeout']?.toString() ?? '') ?? defaultTimeoutSeconds;
    return MimoTtsConfig(
      url: normalizeMimoUrl(map['url']?.toString() ?? ''),
      apiKey: map['key']?.toString() ?? '',
      model: map['model']?.toString().trim().isNotEmpty == true
          ? map['model'].toString().trim()
          : defaultModel,
      voice: map['voice']?.toString().trim().isNotEmpty == true
          ? map['voice'].toString().trim()
          : defaultVoice,
      format: map['format']?.toString().trim().isNotEmpty == true
          ? map['format'].toString().trim()
          : defaultFormat,
      instruction: map['instruction']?.toString() ?? '',
      timeoutSeconds: timeout > 0 ? timeout : defaultTimeoutSeconds,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'key': apiKey,
        'model': model,
        'voice': voice,
        'format': format,
        'instruction': instruction,
        'timeout': timeoutSeconds,
      };
}

/// Normalize a user-supplied MiMo endpoint.
///
/// Accepts either the full endpoint
/// (`https://host/v1/chat/completions`) or a base URL
/// (`https://host/v1`, optionally with trailing slashes) as documented by
/// OpenAI-compatible clients, and always returns the full endpoint.
String normalizeMimoUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return MimoTtsConfig.defaultUrl;
  if (url.endsWith('/chat/completions')) return url;
  return '${url.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
}

/// Build the HTTP headers for a MiMo TTS request.
///
/// MiMo authenticates with the dedicated `api-key` header.
Map<String, String> buildMimoHeaders(String apiKey) => {
      'api-key': apiKey,
      'Content-Type': 'application/json',
    };

/// A single chat message of the MiMo chat-completions style request.
class MimoChatMessage {
  final String role;
  final String content;

  const MimoChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Build the MiMo `/v1/chat/completions` request body for speech synthesis.
///
/// Per the official docs the text to synthesize is the content of the
/// `assistant` message; the optional `user` message carries a voice/style
/// description and is only required by the voicedesign model, so it is
/// omitted when no [instruction] is configured. MiMo documents no speed or
/// pitch parameters, so none are sent.
Map<String, dynamic> buildMimoRequestBody({
  required String model,
  required String text,
  required String voice,
  required String format,
  String instruction = '',
}) {
  final messages = <MimoChatMessage>[
    if (instruction.trim().isNotEmpty)
      MimoChatMessage(role: 'user', content: instruction.trim()),
    MimoChatMessage(role: 'assistant', content: text),
  ];

  return {
    'model': model,
    'messages': messages.map((message) => message.toJson()).toList(),
    'audio': {
      'voice': voice,
      'format': format,
    },
  };
}

/// Extract the synthesized audio from a MiMo chat-completions JSON response.
///
/// The response is JSON (not a binary stream): the audio is base64 encoded in
/// `choices[0].message.audio.data`. An empty `data` field yields an empty
/// result so the caller can surface it as silence; malformed payloads raise
/// an [Exception] with a readable message.
Uint8List parseMimoResponse(Map<String, dynamic> responseBody) {
  final choices = responseBody['choices'];
  if (choices is! List || choices.isEmpty) {
    throw Exception(
        'MiMo TTS response has no choices: ${_truncate(jsonEncode(responseBody))}');
  }

  Map<String, dynamic>? firstChoice;
  for (final choice in choices) {
    if (choice is Map<String, dynamic>) {
      firstChoice = choice;
      break;
    }
  }
  if (firstChoice == null) {
    throw Exception('MiMo TTS response has an invalid choices entry');
  }

  final finishReason = firstChoice['finish_reason']?.toString() ?? '';
  if (finishReason == 'content_filter') {
    throw Exception(
        'MiMo TTS rejected the text (content filter), please try other content');
  }

  final message = firstChoice['message'];
  if (message is! Map<String, dynamic>) {
    throw Exception('MiMo TTS response has no message object');
  }

  final audio = message['audio'];
  if (audio is! Map<String, dynamic>) {
    throw Exception('MiMo TTS response has no audio object');
  }

  final data = audio['data']?.toString() ?? '';
  if (data.isEmpty) {
    return Uint8List(0);
  }

  try {
    return base64Decode(data);
  } on FormatException {
    throw Exception('MiMo TTS response contains invalid base64 audio data');
  }
}

/// Describe a non-200 MiMo HTTP status with a readable reason.
String describeMimoStatus(int statusCode) {
  switch (statusCode) {
    case 401:
    case 403:
      return 'authentication failed, please check your API key';
    case 429:
      return 'rate limited, please retry later';
    case 400:
      return 'invalid request parameters';
    default:
      return statusCode >= 500 ? 'MiMo server error' : 'unexpected response';
  }
}

String _truncate(String text, [int max = 200]) =>
    text.length <= max ? text : text.substring(0, max);
