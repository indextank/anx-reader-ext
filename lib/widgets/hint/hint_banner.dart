import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';

class HintBanner extends StatefulWidget {
  const HintBanner({
    super.key,
    required this.child,
    this.icon,
    this.hintKey,
    this.onClose,
    this.margin,
    this.padding,
  });

  final Widget child;
  final Widget? icon;
  final HintKey? hintKey;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  State<HintBanner> createState() => _HintBannerState();
}

class _HintBannerState extends State<HintBanner>
    with SingleTickerProviderStateMixin {
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible =
        widget.hintKey == null ? true : Prefs().shouldShowHint(widget.hintKey!);
  }

  void _handleClose() {
    if (!_visible) return;

    widget.onClose?.call();

    if (widget.hintKey != null) {
      Prefs().setShowHint(widget.hintKey!, false);
    }

    AnxToast.show(L10n.of(context).hintBannerRestoreToast);

    setState(() {
      _visible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.primary;
    final backgroundColor = colorScheme.primary.withAlpha(30);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _visible
          ? FilledContainer(
              margin: widget.margin,
              color: backgroundColor,
              child: Stack(
                children: [
                  Padding(
                    // 右侧为 48dp 的 AppIconButton 预留整格，避免 hover pill 压字。
                    padding:
                        AppSpacing.fromLTRB(12, 12, AppSpacing.tokens.s48, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          IconTheme(
                            data: IconTheme.of(context)
                                .copyWith(color: borderColor.withAlpha(220)),
                            child: widget.icon!,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: AppIconButton(
                      icon: Icons.close,
                      tooltip: L10n.of(context).close,
                      onPressed: _handleClose,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
