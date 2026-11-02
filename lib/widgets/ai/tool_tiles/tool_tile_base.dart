import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class ToolTileBase extends StatefulWidget {
  const ToolTileBase({
    super.key,
    required this.title,
    required this.leadingIcon,
    required this.statusColor,
    this.initiallyExpanded = false,
    this.contentBuilder,
  });

  final String title;
  final IconData leadingIcon;
  final Color statusColor;
  final bool initiallyExpanded;
  final WidgetBuilder? contentBuilder;

  bool get expandable => contentBuilder != null;

  static Color statusColorFor(BuildContext context, String status) {
    final colors = context.appTheme.colors;
    switch (status) {
      case 'success':
        return colors.success;
      case 'failed':
        return colors.error;
      default:
        return colors.warning;
    }
  }

  @override
  State<ToolTileBase> createState() => _ToolTileBaseState();
}

class _ToolTileBaseState extends State<ToolTileBase> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    if (!widget.expandable) {
      return;
    }
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: AppAiTokens.toolCardPadding,
      borderRadius: AppAiTokens.toolCardRadius,
      onTap: widget.expandable ? _toggle : null,
      child: Semantics(
        button: widget.expandable,
        expanded: widget.expandable ? _expanded : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.leadingIcon, size: AppAiTokens.toolIconSize),
                SizedBox(width: AppSpacing.tokens.s8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: AppAiTokens.toolStatusSize,
                  height: AppAiTokens.toolStatusSize,
                  decoration: BoxDecoration(
                    color: widget.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (widget.expandable && _expanded) ...[
              SizedBox(height: AppSpacing.tokens.s8),
              widget.contentBuilder!(context),
            ],
          ],
        ),
      ),
    );
  }
}
