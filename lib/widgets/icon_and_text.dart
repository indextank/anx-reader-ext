import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:flutter/material.dart';

class IconAndText extends StatelessWidget {
  final Widget icon;
  final String text;
  final VoidCallback? onTap;
  final double? fontSize;
  final bool compact;

  const IconAndText({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
    this.fontSize,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double width = compact ? 42 : 48;
    final double height = compact ? 50 : 60;

    if (!Prefs().showActionLabels) {
      if (onTap == null) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(child: icon),
        );
      }

      return AppIconButton(
        variant: AppButtonVariant.neutral,
        tooltip: text,
        onPressed: onTap,
        child: icon,
      );
    }

    Widget content = SizedBox(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          SizedBox(height: compact ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              constraints: BoxConstraints(maxWidth: compact ? 72 : 96),
              child: Text(
                text,
                style: TextStyle(fontSize: fontSize),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.border8,
        child: content,
      ),
    );
  }
}
