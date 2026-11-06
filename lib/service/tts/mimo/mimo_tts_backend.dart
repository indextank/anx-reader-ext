import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/mimo/mimo_tts_models.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class MimoTtsProvider extends TtsServiceProvider {
  static final MimoTtsProvider _instance = MimoTtsProvider._();

  factory MimoTtsProvider() => _instance;

  MimoTtsProvider._() : _injectedClient = null;

  /// Creates a fresh instance with an injectable HTTP client for tests.
  @visibleForTesting
  MimoTtsProvider.forTesting({http.Client? client}) : _injectedClient = client;

  final http.Client? _injectedClient;
  static final http.Client _sharedClient = http.Client();

  http.Client get _client => _injectedClient ?? _sharedClient;

  @override
  TtsService get service => TtsService.mimo;

  /// MiMo documents no speed/pitch parameters in the request body. The
  /// pipeline applies the UI rate through the audio player output instead
  /// (`TtsAudioOutput` playback rate), so the slider works without
  /// re-synthesizing and MiMo requests must never invent a speed field.
  @override
  bool get supportsRateParameter => false;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateMimoTts;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateMimoHelpText,
        link: 'https://mimo.mi.com/docs/zh-CN/api/audio/tts',
      ),
      ConfigItem(
        key: 'url',
        label: 'URL',
        description: L10n.of(context).settingsNarrateMimoUrlDescription,
        type: ConfigItemType.text,
        defaultValue: MimoTtsConfig.defaultUrl,
      ),
      ConfigItem(
        key: 'key',
        label: 'API Key',
        description: L10n.of(context).settingsNarrateMimoKeyDescription,
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'model',
        label: 'Model',
        description: L10n.of(context).settingsNarrateMimoModelDescription,
        type: ConfigItemType.select,
        defaultValue: MimoTtsConfig.defaultModel,
        options: [
          for (final model in MimoTtsConfig.modelOptions)
            {'value': model, 'label': model},
        ],
      ),
      ConfigItem(
        key: 'voice',
        label: 'Voice',
        description: L10n.of(context).settingsNarrateMimoVoiceDescription,
        type: ConfigItemType.select,
        defaultValue: MimoTtsConfig.defaultVoice,
        options: [
          for (final voice in mimoVoiceOptions)
            {'value': voice.shortName, 'label': voice.name},
        ],
      ),
      ConfigItem(
        key: 'format',
        label: 'Format',
        description: L10n.of(context).settingsNarrateMimoFormatDescription,
        type: ConfigItemType.select,
        defaultValue: MimoTtsConfig.defaultFormat,
        options: [
          for (final format in MimoTtsConfig.formatOptions)
            {'value': format, 'label': format},
        ],
      ),
      ConfigItem(
        key: 'instruction',
        label: 'Instruction',
        description: L10n.of(context).settingsNarrateMimoInstructionDescription,
        type: ConfigItemType.text,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'timeout',
        label: 'Timeout (s)',
        description: L10n.of(context).settingsNarrateTimeoutDescription,
        type: ConfigItemType.number,
        defaultValue: MimoTtsConfig.defaultTimeoutSeconds,
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    // Re-normalize through the typed config so callers always see defaults.
    return MimoTtsConfig.fromMap(config).toMap();
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = MimoTtsConfig.fromMap(getConfig());

    if (config.apiKey.trim().isEmpty) {
      throw Exception('MiMo TTS config missing (key)');
    }

    // Empty text is treated as an empty result, matching the silent-segment
    // semantics of the playback pipeline. MiMo documents no speed or pitch
    // parameters, so rate/pitch are intentionally not applied.
    if (text.trim().isEmpty) {
      return Uint8List(0);
    }

    final resolvedVoice =
        (voice != null && voice.isNotEmpty) ? voice : getSelectedVoice();
    if (resolvedVoice.isEmpty) {
      throw Exception('MiMo TTS config missing (voice)');
    }

    final requestBody = buildMimoRequestBody(
      model: config.model,
      text: text,
      voice: resolvedVoice,
      format: config.format,
      instruction: config.instruction,
    );

    final response = await _client
        .post(
          Uri.parse(config.url),
          headers: buildMimoHeaders(config.apiKey),
          body: jsonEncode(requestBody),
        )
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode != 200) {
      final reason = describeMimoStatus(response.statusCode);
      final detail = response.body.trim();
      throw Exception(
        'MiMo TTS request failed (HTTP ${response.statusCode}): $reason'
        '${detail.isEmpty ? '' : ' - ${detail.substring(0, detail.length.clamp(0, 200))}'}',
      );
    }

    final Map<String, dynamic> responseBody;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      responseBody = decoded;
    } on FormatException {
      throw Exception('MiMo TTS response is not valid JSON');
    }

    return parseMimoResponse(responseBody);
  }

  @override
  Future<List<TtsVoice>> getVoices() async => mimoVoiceOptions;

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    return MimoTtsConfig.fromMap(getConfig()).voice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }
}

/// Preset voices documented by MiMo for `mimo-v2.5-tts`.
/// The docs do not state a locale per voice, so Chinese-named voices are
/// grouped under zh and English-named ones under en (display-only grouping).
const List<TtsVoice> mimoVoiceOptions = [
  TtsVoice(shortName: 'mimo_default', name: 'MiMo Default', locale: 'zh'),
  TtsVoice(shortName: '冰糖', name: '冰糖', locale: 'zh'),
  TtsVoice(shortName: '茉莉', name: '茉莉', locale: 'zh'),
  TtsVoice(shortName: '苏打', name: '苏打', locale: 'zh'),
  TtsVoice(shortName: '白桦', name: '白桦', locale: 'zh'),
  TtsVoice(shortName: 'Mia', name: 'Mia', locale: 'en'),
  TtsVoice(shortName: 'Chloe', name: 'Chloe', locale: 'en'),
  TtsVoice(shortName: 'Milo', name: 'Milo', locale: 'en'),
  TtsVoice(shortName: 'Dean', name: 'Dean', locale: 'en'),
];
