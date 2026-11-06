import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_engine_activation.dart';
import 'package:anx_reader/service/tts/tts_engine_enablement_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/providers/tts_providers.dart' hide TtsService;
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_engine_enablement.g.dart';

/// 朗读引擎启用状态的加载结果。
enum TtsEngineEnablementLoadStatus {
  /// 成功读取到持久化状态。
  loaded,

  /// 读取失败，已回退到默认值（系统 TTS 开启、第三方引擎关闭）。
  fallbackToDefaults,
}

/// 朗读引擎启用状态的完整快照（强类型、不可变）。
@immutable
class TtsEngineEnablementState {
  const TtsEngineEnablementState({
    required this.registry,
    this.loadStatus = TtsEngineEnablementLoadStatus.loaded,
    this.loadError,
    this.loadStackTrace,
  });

  final TtsEngineEnablementRegistry registry;
  final TtsEngineEnablementLoadStatus loadStatus;
  final Object? loadError;
  final StackTrace? loadStackTrace;

  /// 是否处于"读取失败 → 默认值"回退态（设置页据此展示非阻断提示）。
  bool get usedFallback =>
      loadStatus == TtsEngineEnablementLoadStatus.fallbackToDefaults;

  bool isEnabled(TtsService service) => registry.isEnabled(service);

  List<TtsService> get enabledEngines => registry.enabledEngines;

  TtsEngineEnablementState copyWithRegistry(
    TtsEngineEnablementRegistry nextRegistry,
  ) {
    return TtsEngineEnablementState(
      registry: nextRegistry,
      loadStatus: loadStatus,
      loadError: loadError,
      loadStackTrace: loadStackTrace,
    );
  }

  /// 持久化写入成功后清除"读取失败"回退标记：
  /// 存储已经可写且内容已修复，提示不再需要继续展示。
  TtsEngineEnablementState asRecovered() {
    if (!usedFallback) return this;
    return TtsEngineEnablementState(registry: registry);
  }

  @override
  String toString() => 'TtsEngineEnablementState($registry, $loadStatus)';
}

/// 持久化端口：生产走 [Prefs]，测试可覆盖为内存 Fake。
@Riverpod(keepAlive: true)
TtsEngineEnablementStore ttsEngineEnablementStore(Ref ref) {
  return const PrefsTtsEngineEnablementStore();
}

/// 引擎运行时切换端口：生产走 [TtsHandler]，测试可覆盖为 Fake。
@Riverpod(keepAlive: true)
TtsEngineActivation ttsEngineActivation(Ref ref) {
  return const TtsHandlerEngineActivation();
}

/// 朗读引擎启用状态 provider。
///
/// - 应用启动/首次监听时异步加载持久化状态；
/// - 读取失败回退默认值（系统 TTS 开启、第三方引擎关闭）并标记回退态；
/// - [setEnabled]/[toggle] 乐观更新后按调用顺序串行写入持久化，
///   防止快速连续切换时状态与落盘顺序错乱；
/// - 关闭当前选中的第三方引擎时自动回退到系统 TTS（含运行时切换与选择更新）。
@Riverpod(keepAlive: true)
class TtsEngineEnablement extends _$TtsEngineEnablement {
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<TtsEngineEnablementState> build() async {
    final store = ref.watch(ttsEngineEnablementStoreProvider);
    TtsEngineEnablementState loadedState;
    try {
      final registry = await store.load();
      loadedState = TtsEngineEnablementState(registry: registry);
    } catch (error, stackTrace) {
      AnxLog.severe(
        'Failed to load TTS engine enablement, falling back to defaults: '
        '$error\n$stackTrace',
      );
      loadedState = TtsEngineEnablementState(
        registry: TtsEngineEnablementRegistry.defaults(),
        loadStatus: TtsEngineEnablementLoadStatus.fallbackToDefaults,
        loadError: error,
        loadStackTrace: stackTrace,
      );
    }
    _reconcilePersistedSelection(loadedState.registry);
    return loadedState;
  }

  /// 当前已启用引擎（系统 TTS 恒在首位）；加载中/未就绪时仅系统 TTS。
  List<TtsService> get enabledEngines => state.valueOrNull?.enabledEngines ??
      const <TtsService>[TtsService.system];

  /// 单个引擎是否启用；系统 TTS 恒为 true。
  bool isEnabled(TtsService service) {
    if (service.isSystem) return true;
    return state.valueOrNull?.isEnabled(service) ?? false;
  }

  /// 设置某个引擎的启用状态。
  ///
  /// 系统 TTS 的关闭请求会被忽略（恒开启）；加载中/未就绪时不接受写入，
  /// 避免覆盖尚未读取到的持久化状态。
  Future<void> setEnabled(
    TtsService service, {
    required bool enabled,
  }) async {
    if (service.isSystem) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final registry = current.registry.withEnabled(service, enabled);
    if (registry == current.registry) return;
    // 乐观更新：开关与悬浮条引擎列表立即响应。
    state = AsyncData(current.copyWithRegistry(registry));
    final persisted = _enqueuePersist(registry);
    if (!enabled) {
      await _fallbackSelectedEngineIfDisabled(registry);
    }
    await persisted;
  }

  /// 切换某个引擎的启用状态。
  Future<void> toggle(TtsService service) =>
      setEnabled(service, enabled: !isEnabled(service));

  /// 重新加载持久化状态（读取失败提示里的重试入口）。
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// 串行化写入：每次落盘都排在上一次之后，保证最终持久化值是最后一次
  /// 确认的状态；单次写入失败只记录日志，不回滚用户可见的开关状态。
  Future<void> _enqueuePersist(TtsEngineEnablementRegistry registry) {
    final store = ref.read(ttsEngineEnablementStoreProvider);
    final write = _writeQueue.then<void>((_) async {
      try {
        await store.save(registry);
        final current = state.valueOrNull;
        if (current != null && current.usedFallback) {
          // 写入成功说明存储已恢复正常：清除回退提示（保留最新状态）。
          state = AsyncData(current.asRecovered());
        }
      } catch (error, stackTrace) {
        AnxLog.severe(
          'Failed to persist TTS engine enablement: $error\n$stackTrace',
        );
      }
    });
    _writeQueue = write;
    return write;
  }

  /// 启动对账：若持久化的当前引擎已被停用，把选择回退到系统 TTS。
  ///
  /// 这里只修正持久化选择、不实例化朗读引擎；下一次朗读按 Prefs 创建
  /// 系统引擎，避免应用启动阶段触碰音频插件。
  void _reconcilePersistedSelection(TtsEngineEnablementRegistry registry) {
    final selected = getTtsService(Prefs().ttsService);
    if (selected.isSystem || registry.isEnabled(selected)) return;
    Future<void>.microtask(() {
      Prefs().ttsService = TtsService.system.name;
      ref.invalidate(ttsServiceProvider);
    });
  }

  /// 用户关闭某个引擎后：若它正是当前选中的引擎，自动切换到系统 TTS，
  /// 并刷新选择 provider 使设置页与朗读悬浮条同步显示系统 TTS。
  Future<void> _fallbackSelectedEngineIfDisabled(
    TtsEngineEnablementRegistry registry,
  ) async {
    final selected = getTtsService(Prefs().ttsService);
    if (selected.isSystem || registry.isEnabled(selected)) return;
    try {
      await ref.read(ttsEngineActivationProvider).activate(TtsService.system);
    } catch (error, stackTrace) {
      AnxLog.severe(
        'Failed to fall back the selected TTS engine to system: '
        '$error\n$stackTrace',
      );
    }
    ref.invalidate(ttsServiceProvider);
  }
}

/// 当前已启用引擎列表（系统 TTS 恒在首位）。
///
/// 朗读悬浮条的引擎列表只需监听该派生 provider 做过滤；widget 测试可
/// 通过 `enabledTtsEnginesProvider.overrideWith(...)` 直接注入集合。
@Riverpod(keepAlive: true)
List<TtsService> enabledTtsEngines(Ref ref) {
  final enablement = ref.watch(ttsEngineEnablementProvider);
  return enablement.valueOrNull?.enabledEngines ??
      const <TtsService>[TtsService.system];
}
