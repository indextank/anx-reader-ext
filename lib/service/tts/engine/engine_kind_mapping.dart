import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/tts_service.dart';

/// Maps the persisted service enum to the typed pipeline engine kind.
TtsEngineKind ttsEngineKindForService(TtsService service) {
  switch (service) {
    case TtsService.system:
      return TtsEngineKind.system;
    case TtsService.aliyun:
      return TtsEngineKind.aliyun;
    case TtsService.azure:
      return TtsEngineKind.azure;
    case TtsService.openai:
      return TtsEngineKind.openai;
    case TtsService.stepaudio:
      return TtsEngineKind.stepAudio;
    case TtsService.mimo:
      return TtsEngineKind.mimo;
  }
}

/// Maps a typed engine kind back to the persisted service enum (fake engines
/// fall back to system for preference resolution).
TtsService ttsServiceForEngineKind(TtsEngineKind kind) {
  switch (kind) {
    case TtsEngineKind.system:
    case TtsEngineKind.fake:
      return TtsService.system;
    case TtsEngineKind.aliyun:
      return TtsService.aliyun;
    case TtsEngineKind.azure:
      return TtsService.azure;
    case TtsEngineKind.openai:
      return TtsService.openai;
    case TtsEngineKind.stepAudio:
      return TtsService.stepaudio;
    case TtsEngineKind.mimo:
      return TtsService.mimo;
  }
}

/// Engine kind for the currently persisted service id.
TtsEngineKind currentTtsEngineKind(String serviceId) =>
    ttsEngineKindForService(getTtsService(serviceId));
