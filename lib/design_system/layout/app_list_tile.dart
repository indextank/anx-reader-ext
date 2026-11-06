import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:flutter/material.dart';

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.contentPadding,
    this.semanticLabel,
    this.titleMaxLines,
    this.subtitleMaxLines,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 行内边距；默认取样式面板当前密度（常规 16、紧凑 8），
  /// 面板外仍为 16，兼容既有页面。
  final EdgeInsetsGeometry? contentPadding;
  final String? semanticLabel;

  /// 标题最大行数；设置后超长省略（默认不限制，保持既有行为）。
  final int? titleMaxLines;

  /// 副标题最大行数；设置后超长省略。
  final int? subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: Semantics(
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: Text(
          title,
          maxLines: titleMaxLines,
          overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Semantics(
              excludeSemantics: semanticLabel != null,
              child: Text(
                subtitle!,
                maxLines: subtitleMaxLines,
                overflow:
                    subtitleMaxLines == null ? null : TextOverflow.ellipsis,
              ),
            ),
      trailing: trailing,
      enabled: enabled,
      selected: selected,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      contentPadding:
          contentPadding ?? StylePanelDensity.of(context).tileContentPadding,
      minTileHeight: AppSpacing.tokens.s48,
    );
  }
}
