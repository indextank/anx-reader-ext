import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        context.appTheme.isEInk || MediaQuery.disableAnimationsOf(context);
    final skeleton = Skeletonizer(
      enabled: enabled,
      effect: reduceMotion
          ? SoldColorEffect(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            )
          : null,
      enableSwitchAnimation: reduceMotion ? false : null,
      child: child,
    );
    if (!enabled) return skeleton;
    return Semantics(
      label: L10n.of(context).commonLoading,
      container: true,
      child: ExcludeSemantics(child: skeleton),
    );
  }
}
