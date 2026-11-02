import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppPageTransitions extends PageTransitionsBuilder {
  const AppPageTransitions();

  static PageRouteBuilder<T> route<T>({
    required Widget child,
    RouteSettings? settings,
  }) {
    late final PageRouteBuilder<T> route;
    const transitions = AppPageTransitions();
    route = PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.tokens.normal,
      reverseTransitionDuration: AppMotion.tokens.fast,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return transitions.buildTransitions<T>(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
      },
    );
    return route;
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.appTheme.isEInk || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
