import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_panel_position.g.dart';

/// 样式面板展现位置（枚举，非裸字符串）的 Riverpod 持有者。
///
/// 读取跟随 Prefs（含写入期间的乐观 runtimeValue）；[set] 乐观更新
/// 本 provider 状态并异步落盘，失败回滚为 popup。
@Riverpod(keepAlive: true)
class StylePanelPosition extends _$StylePanelPosition {
  @override
  AiPanelPositionEnum build() {
    final prefs = Prefs();
    void onPreferencesChanged() {
      // Prefs 可能在其它 provider 初始化期间同步通知；延迟到微任务，
      // 避免在构建中修改 provider（riverpod 断言）。
      Future<void>.microtask(() {
        final latest = prefs.stylePanelPosition;
        if (state != latest) state = latest;
      });
    }

    prefs.addListener(onPreferencesChanged);
    ref.onDispose(() => prefs.removeListener(onPreferencesChanged));
    return prefs.stylePanelPosition;
  }

  void set(AiPanelPositionEnum value) {
    final previous = state;
    state = value;
    Prefs().stylePanelPosition = value;
    // Prefs 写入失败会通过 listener 通知回滚；这里补充监听无法覆盖的
    // 极端情形（listener 未触发时以 Prefs 实际值自愈）。
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (state == value && Prefs().stylePanelPosition != value) {
        state = previous;
      }
    });
  }
}
