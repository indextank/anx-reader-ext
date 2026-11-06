import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';

/// 朗读引擎启用状态的持久化端口（可注入，便于单元测试）。
///
/// 生产实现沿用项目既有的 [Prefs]（shared_preferences）方案，与其它
/// 设置项的持久化路径一致，重启应用后状态保持不变。
abstract interface class TtsEngineEnablementStore {
  /// 读取已持久化的启用状态；读取/解析失败时抛出
  /// [TtsEngineEnablementLoadException]。
  Future<TtsEngineEnablementRegistry> load();

  /// 写入启用状态（只保存第三方引擎 id，系统 TTS 恒开启不入库）。
  Future<void> save(TtsEngineEnablementRegistry registry);
}

/// 基于 [Prefs] 的生产持久化实现。
class PrefsTtsEngineEnablementStore implements TtsEngineEnablementStore {
  const PrefsTtsEngineEnablementStore();

  @override
  Future<TtsEngineEnablementRegistry> load() async {
    try {
      return TtsEngineEnablementRegistry.fromStoredIds(
        Prefs().ttsEnabledEngineIds,
      );
    } catch (error, stackTrace) {
      throw TtsEngineEnablementLoadException(error, stackTrace);
    }
  }

  @override
  Future<void> save(TtsEngineEnablementRegistry registry) async {
    Prefs().ttsEnabledEngineIds =
        registry.toStoredIds().toList(growable: false);
  }
}

/// 持久化读取失败：偏好缺失/损坏或存储异常。
///
/// 上层（`ttsEngineEnablementProvider`）捕获后回退到默认值（系统 TTS
/// 开启、第三方引擎关闭）并给出可感知但不打断流程的提示。
class TtsEngineEnablementLoadException implements Exception {
  const TtsEngineEnablementLoadException(this.cause, this.stackTrace);

  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'TtsEngineEnablementLoadException($cause)';
}
