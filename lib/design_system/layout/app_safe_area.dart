import 'dart:math' as math;

import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppSafeArea extends StatelessWidget {
  const AppSafeArea({
    super.key,
    required this.child,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.avoidViewInsets = true,
    this.minimum = AppSpacing.zero,
    this.maintainBottomViewPadding = false,
  });

  final Widget child;
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final bool avoidViewInsets;
  final EdgeInsets minimum;
  final bool maintainBottomViewPadding;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeBottom = bottom ? mediaQuery.padding.bottom : 0.0;
    final insetBottom =
        bottom && avoidViewInsets ? mediaQuery.viewInsets.bottom : 0.0;
    final additionalBottom = math.max(0.0, insetBottom - safeBottom);

    return SafeArea(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      minimum: minimum,
      maintainBottomViewPadding: maintainBottomViewPadding,
      child: Padding(
        padding: AppSpacing.only(bottom: additionalBottom),
        child: child,
      ),
    );
  }
}
