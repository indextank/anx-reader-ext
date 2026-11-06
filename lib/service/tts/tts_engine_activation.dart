import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_service.dart';

/// 切换当前朗读引擎的运行时动作端口（可注入，便于单元测试）。
///
/// 启用状态 provider 在"用户关闭当前选中的第三方引擎"时会调用
/// [activate] 回退到系统 TTS；生产实现复用 [TtsHandler] 的引擎切换
/// （包含游标迁移与偏好持久化），测试注入 Fake 即可观察调用。
abstract interface class TtsEngineActivation {
  Future<void> activate(TtsService service);
}

/// 生产实现：委托给现有 [TtsHandler] 单例。
class TtsHandlerEngineActivation implements TtsEngineActivation {
  const TtsHandlerEngineActivation();

  @override
  Future<void> activate(TtsService service) =>
      TtsHandler().switchTtsType(service.name);
}
