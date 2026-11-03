import 'package:anx_reader/theme/app_spacing.dart';
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
    this.contentPadding = AppSpacing.horizontal16,
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
  final EdgeInsetsGeometry contentPadding;
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
      contentPadding: contentPadding,
      minTileHeight: AppSpacing.tokens.s48,
    );
  }
}
