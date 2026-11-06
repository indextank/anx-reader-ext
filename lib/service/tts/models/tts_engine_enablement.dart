import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter/foundation.dart';

/// 单个 TTS 引擎的启用状态（强类型、不可变）。
///
/// 类型层面的约束：系统 TTS 只能通过 [TtsEngineEnablement.system] 构造，
/// 其 [enabled] 恒为 true；第三方引擎通过 [TtsEngineEnablement.thirdParty]
/// 构造，断言拒绝把系统 TTS 当作第三方引擎传入。因此不存在
/// "系统 TTS 被关闭" 的合法取值。
@immutable
class TtsEngineEnablement {
  /// 系统 TTS：恒为开启。
  const TtsEngineEnablement.system()
      : service = TtsService.system,
        enabled = true;

  /// 第三方引擎：启用状态由配置决定（构造时断言非系统 TTS）。
  const TtsEngineEnablement.thirdParty(
    this.service, {
    required this.enabled,
  }) : assert(
          service != TtsService.system,
          'System TTS is always enabled; use TtsEngineEnablement.system()',
        );

  /// 按引擎类型选择合适的构造方式；系统 TTS 的 [enabled] 会被强制为 true。
  factory TtsEngineEnablement.of(
    TtsService service, {
    required bool enabled,
  }) {
    return service.isSystem
        ? const TtsEngineEnablement.system()
        : TtsEngineEnablement.thirdParty(service, enabled: enabled);
  }

  final TtsService service;
  final bool enabled;

  bool get isSystem => service.isSystem;

  /// 派生一个新的启用状态；系统 TTS 保持恒开启。
  TtsEngineEnablement withEnabled(bool value) =>
      TtsEngineEnablement.of(service, enabled: value);

  @override
  bool operator ==(Object other) =>
      other is TtsEngineEnablement &&
      other.service == service &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(service, enabled);

  @override
  String toString() =>
      'TtsEngineEnablement(${service.name}, enabled: $enabled)';
}

/// 全部 TTS 引擎启用状态的强类型快照（不可变）。
///
/// 内部只用 [TtsService] 集合表达第三方引擎，系统 TTS 不进入集合：
/// [isEnabled] 对系统 TTS 恒返回 true，[enabledEngines] 恒包含系统 TTS。
/// 这样"系统 TTS 恒开启"由数据结构本身保证，而不是依赖调用方自律。
@immutable
class TtsEngineEnablementRegistry {
  TtsEngineEnablementRegistry._(Set<TtsService> enabledThirdParty)
      : _enabledThirdParty = Set<TtsService>.unmodifiable(enabledThirdParty);

  /// 默认值：系统 TTS 开启，第三方引擎全部关闭。
  factory TtsEngineEnablementRegistry.defaults() =>
      TtsEngineEnablementRegistry._(<TtsService>{});

  /// 从一组引擎构造：系统 TTS 恒开启，非系统引擎进入启用集合。
  factory TtsEngineEnablementRegistry.fromEnabledServices(
    Iterable<TtsService> enabledServices,
  ) {
    final enabled = <TtsService>{};
    for (final service in enabledServices) {
      if (service.isThirdParty) enabled.add(service);
    }
    return TtsEngineEnablementRegistry._(enabled);
  }

  /// 从持久化的引擎 id 构造；未知 id、系统 TTS id 会被忽略。
  factory TtsEngineEnablementRegistry.fromStoredIds(
    Iterable<String> storedIds,
  ) {
    final enabled = <TtsService>{};
    for (final id in storedIds) {
      final service = TtsService.tryParse(id);
      if (service != null && service.isThirdParty) enabled.add(service);
    }
    return TtsEngineEnablementRegistry._(enabled);
  }

  final Set<TtsService> _enabledThirdParty;

  /// 引擎是否启用；系统 TTS 恒为 true。
  bool isEnabled(TtsService service) =>
      service.isSystem || _enabledThirdParty.contains(service);

  /// 已启用引擎，按系统 TTS → 第三方声明顺序排列；系统 TTS 恒在首位。
  List<TtsService> get enabledEngines => <TtsService>[
        TtsService.system,
        for (final service in TtsService.thirdPartyServices)
          if (_enabledThirdParty.contains(service)) service,
      ];

  /// 每个引擎的强类型启用状态（含系统 TTS 的恒开启项）。
  List<TtsEngineEnablement> get enablements => <TtsEngineEnablement>[
        const TtsEngineEnablement.system(),
        for (final service in TtsService.thirdPartyServices)
          TtsEngineEnablement.thirdParty(
            service,
            enabled: _enabledThirdParty.contains(service),
          ),
      ];

  /// 派生新的快照；系统 TTS 的关闭请求被忽略（保持恒开启）。
  TtsEngineEnablementRegistry withEnabled(
    TtsService service,
    bool enabled,
  ) {
    if (service.isSystem) return this;
    final next = Set<TtsService>.of(_enabledThirdParty);
    if (enabled) {
      next.add(service);
    } else {
      next.remove(service);
    }
    if (setEquals(next, _enabledThirdParty)) return this;
    return TtsEngineEnablementRegistry._(next);
  }

  /// 持久化用的第三方引擎 id 集合（不含系统 TTS）。
  Set<String> toStoredIds() => <String>{
        for (final service in _enabledThirdParty) service.name,
      };

  @override
  bool operator ==(Object other) =>
      other is TtsEngineEnablementRegistry &&
      setEquals(other._enabledThirdParty, _enabledThirdParty);

  @override
  int get hashCode => Object.hashAllUnordered(_enabledThirdParty);

  @override
  String toString() =>
      'TtsEngineEnablementRegistry(enabled: ${enabledEngines.map((e) => e.name).join(', ')})';
}
