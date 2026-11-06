import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/aliyun/aliyun_tts_backend.dart';
import 'package:anx_reader/service/tts/azure_tts_backend.dart';
import 'package:anx_reader/service/tts/mimo/mimo_tts_backend.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:anx_reader/service/tts/step_audio/step_audio_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/material.dart';

/// TTS service enumeration.
/// Defines available TTS services (system TTS and online TTS services).
enum TtsService {
  system,
  aliyun,
  azure,
  openai,
  stepaudio,
  mimo;
  // Future services can be added here: google, aws, elevenlabs, etc.

  /// Get the provider for this TTS service.
  TtsServiceProvider get provider {
    switch (this) {
      case TtsService.system:
        return SystemTtsProvider();
      case TtsService.aliyun:
        return AliyunTtsProvider();
      case TtsService.azure:
        return AzureTtsProvider();
      case TtsService.openai:
        return OpenAiTtsProvider();
      case TtsService.stepaudio:
        return StepAudioTtsProvider();
      case TtsService.mimo:
        return MimoTtsProvider();
    }
  }

  /// Get the display label from the provider.
  String getLabel(BuildContext context) => provider.getLabel(context);

  /// 系统 TTS：始终启用、不可关闭、不参与第三方引擎开关列表。
  bool get isSystem => this == TtsService.system;

  /// 第三方（在线）引擎：可在设置中单独启用/停用。
  bool get isThirdParty => !isSystem;

  /// Check if the service is an online TTS provider.
  bool get isOnline => isThirdParty;

  /// 所有第三方引擎，按 [values] 的声明顺序（不含系统 TTS）。
  static List<TtsService> get thirdPartyServices => values
      .where((service) => service.isThirdParty)
      .toList(growable: false);

  /// 由持久化的引擎 id（[name]）解析枚举；未知 id 返回 null。
  static TtsService? tryParse(String serviceId) {
    for (final service in values) {
      if (service.name == serviceId) return service;
    }
    return null;
  }
}

/// Get TTS service from service ID string.
TtsService getTtsService(String serviceId) =>
    TtsService.tryParse(serviceId) ?? TtsService.system;

/// System TTS provider (placeholder for service provider pattern).
/// System TTS doesn't need configuration, so it returns empty config items.
class SystemTtsProvider extends TtsServiceProvider {
  @override
  TtsService get service => TtsService.system;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateSystemTts;
}
