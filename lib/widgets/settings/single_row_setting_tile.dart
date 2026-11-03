import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 单行设置项：标题（可选副标题、前置图标）居左，控件或当前值居右，
/// 整行垂直居中，点击热区覆盖整行（基于 [AppListTile]，自带
/// InkWell、≥48dp 最小行高、RTL 与语义）。
///
/// 右侧默认包裹横向滚动并限制最大宽度（[trailingMaxWidthFactor]），
/// 保证窄屏与大字号下优先压缩控件而不是标题；Slider 这类需要占满
/// 剩余宽度的控件改用 [pinnedTrailing]，以 Flexible 参与空间分配。
/// 数据未就绪时可用 [loading] 展示单行骨架占位，值缺失或不可用时
/// 通过 [enabled] 进入禁用态兜底。
class SingleRowSettingTile extends StatelessWidget {
  const SingleRowSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.valueLabel,
    this.pinnedTrailing = false,
    this.trailingMaxWidthFactor = 0.68,
    this.minTrailingWidth,
    this.loading = false,
    this.onTap,
    this.enabled = true,
    this.contentPadding,
  });

  /// 标题。行内空间不足时最多两行并省略。
  final String title;

  /// 可选副标题（说明/警示文案），展示在标题下方。
  final String? subtitle;

  /// 可选前置图标。
  final Widget? leading;

  /// 右侧控件（开关、分段按钮、下拉框、滑杆等）。
  final Widget? trailing;

  /// 控件左侧展示的当前值文本（如 "720px"）。
  final String? valueLabel;

  /// true 时 [trailing] 不包横向滚动，直接以 Flexible 参与行内
  /// 剩余空间分配（适用于 Slider、Wrap 等自伸缩控件）。
  final bool pinnedTrailing;

  /// 非钉合模式下 trailing 区域最大宽度占整行可用宽度的比例，
  /// 保证标题至少保留约三分之一。
  final double trailingMaxWidthFactor;

  /// trailing 区域最小宽度约束（可选）。
  final double? minTrailingWidth;

  /// 加载中：右侧以单行骨架占位，控件与回调不可用。
  final bool loading;

  final VoidCallback? onTap;

  final bool enabled;

  /// 行内边距；默认水平 16、垂直 4（EdgeInsetsDirectional，兼容 RTL）。
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxTrailingWidth = constraints.maxWidth * trailingMaxWidthFactor;
      return AppListTile(
        title: title,
        subtitle: subtitle,
        leading: leading,
        enabled: enabled && !loading,
        onTap: onTap,
        titleMaxLines: 2,
        subtitleMaxLines: 2,
        contentPadding: contentPadding ?? AppSpacing.horizontal16,
        trailing: _buildTrailing(context, maxTrailingWidth),
      );
    });
  }

  Widget? _buildTrailing(BuildContext context, double maxTrailingWidth) {
    if (loading) {
      return AppSkeleton(
        child: Text(
          valueLabel ?? '·····',
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (trailing == null && valueLabel == null) return null;

    final theme = Theme.of(context);
    final value = valueLabel == null
        ? null
        : Text(
            valueLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );

    final gap = SizedBox(width: AppSpacing.tokens.s8);
    Widget content;
    if (pinnedTrailing && trailing != null) {
      // 钉合模式：以明确宽度占位（行宽 × 比例），内部 Expanded 分配，
      // 避免 ListTile 的"trailing 占满整行"断言，同时保证滑杆等控件
      // 贴右缘且不挤压标题。
      content = SizedBox(
        width: maxTrailingWidth,
        child: Row(
          children: [
            if (value != null) ...[value, gap],
            Expanded(child: trailing!),
          ],
        ),
      );
    } else {
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) ...[value, gap],
            if (trailing != null) trailing!,
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minTrailingWidth ?? 0,
        maxWidth: maxTrailingWidth,
      ),
      child: content,
    );
  }
}
