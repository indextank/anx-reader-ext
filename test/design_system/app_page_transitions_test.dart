import 'package:anx_reader/design_system/feedback/app_page_transitions.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  test('AppPageTransitions route uses shared motion durations', () {
    final route = AppPageTransitions.route<void>(
      child: const Text('Next page'),
    );
    expect(route.transitionDuration, AppMotion.tokens.normal);
    expect(route.reverseTransitionDuration, AppMotion.tokens.fast);
  });

  testWidgets('normal pages use fade and slide transitions', (tester) async {
    await pumpDesignSystem(
      tester,
      Builder(
        builder: (context) {
          final transition = _buildTransition(context);
          expect(transition, isA<FadeTransition>());
          expect((transition as FadeTransition).child, isA<SlideTransition>());
          return transition;
        },
      ),
    );
    expect(find.text('Page content'), findsOneWidget);
  });

  testWidgets('e-ink and disabled animations return content directly',
      (tester) async {
    await pumpDesignSystem(
      tester,
      Builder(
        builder: (context) {
          final transition = _buildTransition(context);
          expect(transition, isA<Text>());
          return transition;
        },
      ),
      eInkMode: true,
    );
    expect(find.text('Page content'), findsOneWidget);

    await pumpDesignSystem(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            final transition = _buildTransition(context);
            expect(transition, isA<Text>());
            return transition;
          },
        ),
      ),
    );
    expect(find.text('Page content'), findsOneWidget);
  });
}

Widget _buildTransition(BuildContext context) {
  final route = PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) =>
        const SizedBox.shrink(),
  );
  return const AppPageTransitions().buildTransitions<void>(
    route,
    context,
    kAlwaysCompleteAnimation,
    kAlwaysDismissedAnimation,
    const Text('Page content'),
  );
}
