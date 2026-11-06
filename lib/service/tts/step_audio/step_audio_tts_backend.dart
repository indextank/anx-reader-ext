import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/step_audio/step_audio_tts_models.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class StepAudioTtsProvider extends TtsServiceProvider {
  static final StepAudioTtsProvider _instance = StepAudioTtsProvider._();

  factory StepAudioTtsProvider() => _instance;

  StepAudioTtsProvider._() : _injectedClient = null;

  /// Creates a fresh instance with an injectable HTTP client for tests.
  @visibleForTesting
  StepAudioTtsProvider.forTesting({http.Client? client})
      : _injectedClient = client;

  final http.Client? _injectedClient;
  static final http.Client _sharedClient = http.Client();

  http.Client get _client => _injectedClient ?? _sharedClient;

  @override
  TtsService get service => TtsService.stepaudio;

  /// StepFun documents a 1000-character limit for `input`.
  @override
  int get maxRequestChars => 1000;

  @override
  String get documentedRequestLimitNote =>
      'StepFun audio/speech documents a 1000-character limit for input';

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateStepAudioTts;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateStepAudioHelpText,
        link:
            'https://platform.stepfun.com/docs/zh/api-reference/audio/create-audio',
      ),
      ConfigItem(
        key: 'url',
        label: 'URL',
        description: L10n.of(context).settingsNarrateStepAudioUrlDescription,
        type: ConfigItemType.text,
        defaultValue: StepAudioTtsConfig.defaultUrl,
      ),
      ConfigItem(
        key: 'key',
        label: 'API Key',
        description: L10n.of(context).settingsNarrateStepAudioKeyDescription,
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'model',
        label: 'Model',
        description: L10n.of(context).settingsNarrateStepAudioModelDescription,
        type: ConfigItemType.select,
        defaultValue: StepAudioTtsConfig.defaultModel,
        options: [
          for (final model in StepAudioTtsConfig.modelOptions)
            {'value': model, 'label': model},
        ],
      ),
      ConfigItem(
        key: 'voice',
        label: 'Voice',
        description: L10n.of(context).settingsNarrateStepAudioVoiceDescription,
        type: ConfigItemType.text,
        defaultValue: StepAudioTtsConfig.defaultVoice,
      ),
      ConfigItem(
        key: 'responseFormat',
        label: 'Format',
        description: L10n.of(context).settingsNarrateStepAudioFormatDescription,
        type: ConfigItemType.select,
        defaultValue: StepAudioTtsConfig.defaultResponseFormat,
        options: [
          for (final format in StepAudioTtsConfig.responseFormatOptions)
            {'value': format, 'label': format},
        ],
      ),
      ConfigItem(
        key: 'textNormalization',
        label: 'Text Normalization',
        description:
            L10n.of(context).settingsNarrateStepAudioNormalizationDescription,
        type: ConfigItemType.select,
        defaultValue: StepAudioTtsConfig.defaultTextNormalization,
        options: [
          for (final value in StepAudioTtsConfig.textNormalizationOptions)
            {'value': value, 'label': value},
        ],
      ),
      ConfigItem(
        key: 'timeout',
        label: 'Timeout (s)',
        description: L10n.of(context).settingsNarrateTimeoutDescription,
        type: ConfigItemType.number,
        defaultValue: StepAudioTtsConfig.defaultTimeoutSeconds,
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    // Re-normalize through the typed config so callers always see defaults.
    return StepAudioTtsConfig.fromMap(config).toMap();
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = StepAudioTtsConfig.fromMap(getConfig());

    if (config.apiKey.trim().isEmpty) {
      throw Exception('StepAudio TTS config missing (key)');
    }

    // Empty text is treated as an empty result, matching the silent-segment
    // semantics of the playback pipeline.
    if (text.trim().isEmpty) {
      return Uint8List(0);
    }

    final resolvedVoice =
        (voice != null && voice.isNotEmpty) ? voice : getSelectedVoice();
    if (resolvedVoice.isEmpty) {
      throw Exception('StepAudio TTS config missing (voice)');
    }

    final requestBody = buildStepAudioRequestBody(
      model: config.model,
      input: text,
      voice: resolvedVoice,
      responseFormat: config.responseFormat,
      speed: clampStepAudioSpeed(rate),
      textNormalization: config.textNormalization,
    );

    final response = await _client
        .post(
          Uri.parse(config.url),
          headers: buildStepAudioHeaders(config.apiKey),
          body: jsonEncode(requestBody),
        )
        .timeout(Duration(seconds: config.timeoutSeconds));

    return parseStepAudioResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      bodyText: response.body,
    );
  }

  /// Official preset voices from the StepFun docs
  /// (https://platform.stepfun.com/docs/zh/guides/developer/tts.md).
  /// Every voice supports the default model `step-tts-2`; custom
  /// developer-created voice IDs can still be typed in the voice config.
  static const List<TtsVoice> officialVoices = [
    TtsVoice(
        shortName: 'vibrant-youth',
        name: 'Vibrant Youth',
        locale: 'zh',
        description: '有声书、视频配音'),
    TtsVoice(
        shortName: 'lively-girl',
        name: 'Lively Girl',
        locale: 'zh',
        gender: 'female',
        description: '有声书、视频配音'),
    TtsVoice(
        shortName: 'soft-spoken-gentleman',
        name: 'Soft-spoken Gentleman',
        locale: 'zh',
        gender: 'male',
        description: '情感陪伴、有声书'),
    TtsVoice(
        shortName: 'magnetic-voiced-male',
        name: 'Magnetic-voiced Male',
        locale: 'zh',
        gender: 'male',
        description: '有声书、视频配音'),
    TtsVoice(
        shortName: 'zixinnansheng',
        name: '自信男声',
        locale: 'zh',
        gender: 'male',
        description: '有声书、情感陪伴、教育与培训、营销'),
    TtsVoice(
        shortName: 'elegantgentle-female',
        name: '气质温婉',
        locale: 'zh',
        gender: 'female',
        description: '客服与业务办理、口播、教育与培训、情感陪伴'),
    TtsVoice(
        shortName: 'livelybreezy-female',
        name: '活力轻快',
        locale: 'zh',
        gender: 'female',
        description: '情感陪伴、客服、教育与培训、营销'),
    TtsVoice(
        shortName: 'wenrounansheng',
        name: '温柔男声',
        locale: 'zh',
        gender: 'male',
        description: '口播、情感陪伴、客服、教育与培训'),
    TtsVoice(
        shortName: 'wenrougongzi',
        name: '温柔公子',
        locale: 'zh',
        gender: 'male',
        description: '情感陪伴、有声书'),
    TtsVoice(
        shortName: 'yuanqinansheng',
        name: '元气男声',
        locale: 'zh',
        gender: 'male',
        description: '有声书、口播、客服'),
    TtsVoice(
        shortName: 'jingdiannvsheng',
        name: '经典女声',
        locale: 'zh',
        gender: 'female',
        description: '客服、情感陪伴'),
    TtsVoice(
        shortName: 'wenroushunv',
        name: '温柔熟女',
        locale: 'zh',
        gender: 'female',
        description: '客服、口播、教育与培训'),
    TtsVoice(
        shortName: 'tianmeinvsheng',
        name: '甜美女声',
        locale: 'zh',
        gender: 'female',
        description: '情感陪伴、客服'),
    TtsVoice(
        shortName: 'qingchunshaonv',
        name: '清纯少女',
        locale: 'zh',
        gender: 'female',
        description: '客服、语音助手'),
    TtsVoice(
        shortName: 'cixingnansheng',
        name: '磁性男声',
        locale: 'zh',
        gender: 'male',
        description: '有声书、情感陪伴'),
    TtsVoice(
        shortName: 'yuanqishaonv',
        name: '元气少女',
        locale: 'zh',
        gender: 'female',
        description: '有声书、情感陪伴、语音助手'),
    TtsVoice(
        shortName: 'linjiajiejie',
        name: '邻家姐姐',
        locale: 'zh',
        gender: 'female',
        description: '口播、情感陪伴、语音助手、视频配音'),
    TtsVoice(
        shortName: 'zhengpaiqingnian',
        name: '正派青年',
        locale: 'zh',
        gender: 'male',
        description: '营销、有声书'),
    TtsVoice(
        shortName: 'qingniandaxuesheng',
        name: '青年大学生',
        locale: 'zh',
        gender: 'male',
        description: '口播（解说、新闻）'),
    TtsVoice(
        shortName: 'boyinnansheng',
        name: '播音男声',
        locale: 'zh',
        gender: 'male',
        description: '有声书、口播'),
    TtsVoice(
        shortName: 'ruyananshi',
        name: '儒雅男士',
        locale: 'zh',
        gender: 'male',
        description: '有声书、情感陪伴、口播、语音助手'),
    TtsVoice(
        shortName: 'shenchennanyin',
        name: '深沉男音',
        locale: 'zh',
        gender: 'male',
        description: '情感陪伴、有声书'),
    TtsVoice(
        shortName: 'qinqienvsheng',
        name: '亲切女声',
        locale: 'zh',
        gender: 'female',
        description: '口播（解说、新闻）'),
    TtsVoice(
        shortName: 'wenrounvsheng',
        name: '温柔女声',
        locale: 'zh',
        gender: 'female',
        description: '有声书、情感陪伴'),
    TtsVoice(
        shortName: 'jilingshaonv',
        name: '机灵少女',
        locale: 'zh',
        gender: 'female',
        description: '语音助手、口播'),
    TtsVoice(
        shortName: 'ruanmengnvsheng',
        name: '软萌女声',
        locale: 'zh',
        gender: 'female',
        description: '情感陪伴、语音助手、视频配音'),
    TtsVoice(
        shortName: 'youyanvsheng',
        name: '优雅女声',
        locale: 'zh',
        gender: 'female',
        description: '视频配音'),
    TtsVoice(
        shortName: 'lengyanyujie',
        name: '冷艳御姐',
        locale: 'zh',
        gender: 'female',
        description: '视频配音'),
    TtsVoice(
        shortName: 'shuangkuaijiejie',
        name: '爽快姐姐',
        locale: 'zh',
        gender: 'female',
        description: '口播（解说、新闻）'),
    TtsVoice(
        shortName: 'wenjingxuejie',
        name: '文静学姐',
        locale: 'zh',
        gender: 'female',
        description: '口播（解说、新闻）'),
    TtsVoice(
        shortName: 'linjiameimei',
        name: '邻家妹妹',
        locale: 'zh',
        gender: 'female',
        description: '视频配音、口播、语音助手'),
    TtsVoice(
        shortName: 'zhixingjiejie',
        name: '知性姐姐',
        locale: 'zh',
        gender: 'female',
        description: '视频配音、口播、语音助手'),
    TtsVoice(
        shortName: 'shuangkuainansheng',
        name: '爽快男声',
        locale: 'zh',
        gender: 'male',
        description: '客服、语音助手'),
    TtsVoice(
        shortName: 'ganliannvsheng',
        name: '干练女声',
        locale: 'zh',
        gender: 'female',
        description: '客服、语音助手'),
    TtsVoice(
        shortName: 'qinhenvsheng',
        name: '亲和女声',
        locale: 'zh',
        gender: 'female',
        description: '客服、语音助手'),
    TtsVoice(
        shortName: 'huolinvsheng',
        name: '活力女声',
        locale: 'zh',
        gender: 'female',
        description: '客服、语音助手'),
  ];

  @override
  Future<List<TtsVoice>> getVoices() async {
    return officialVoices;
  }

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
    return StepAudioTtsConfig.fromMap(getConfig()).voice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }
}
