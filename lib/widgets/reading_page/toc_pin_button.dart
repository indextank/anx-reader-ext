import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 目录固定开关按钮的稳定 Key（悬浮弹框与固定侧栏共用）。
const tocPinButtonKey = ValueKey('toc-pin-button');

/// 目录固定 / 取消固定按钮。
///
/// 独立 widget：固定状态唯一来源是 [tocPinnedProvider]，点击只提交一次
/// 状态切换；阅读页监听该 provider 负责同步"关闭悬浮弹框 / 恢复悬浮
/// 弹框"，因此快速连点也只会得到单一确定状态，不会叠加侧栏或残留遮罩。
///
/// 未固定显示解锁图标 [Icons.lock_open]，已固定显示锁定图标
/// [Icons.lock]；tooltip / semanticLabel 描述点击后的动作。
class TocPinButton extends ConsumerWidget {
  const TocPinButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(tocPinnedProvider);
    final l10n = L10n.of(context);
    final label = pinned ? l10n.readingTocUnpin : l10n.readingTocPin;
    return AppIconButton(
      key: tocPinButtonKey,
      tooltip: label,
      semanticLabel: label,
      onPressed: () => ref.read(tocPinnedProvider.notifier).toggle(),
      child: Icon(pinned ? Icons.lock : Icons.lock_open),
    );
  }
}
