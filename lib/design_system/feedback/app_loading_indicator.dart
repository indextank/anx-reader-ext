import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

enum AppLoadingIndicatorSize { button, block }

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = AppLoadingIndicatorSize.block,
    this.color,
    this.semanticLabel,
  });

  final AppLoadingIndicatorSize size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        context.appTheme.isEInk || MediaQuery.disableAnimationsOf(context);
    final dimension = switch (size) {
      AppLoadingIndicatorSize.button => AppSpacing.tokens.s20,
      AppLoadingIndicatorSize.block => AppSpacing.tokens.s32,
    };
    return Semantics(
      label: semanticLabel ?? L10n.of(context).commonLoading,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: dimension,
          child: CircularProgressIndicator(
            value: reduceMotion ? 0.25 : null,
            strokeWidth: size == AppLoadingIndicatorSize.button ? 2 : 3,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
