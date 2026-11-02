import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/feedback/app_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('e-ink keeps skeleton content with a static painting effect',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const AppSkeleton(child: Text('Loading row')),
      eInkMode: true,
    );

    final skeleton = tester.widget<Skeletonizer>(
      find.byWidgetPredicate((widget) => widget is Skeletonizer),
    );
    expect(skeleton.enabled, isTrue);
    expect(skeleton.effect, isA<SoldColorEffect>());
    expect(skeleton.effect?.duration, Duration.zero);
    expect(find.text('Loading row'), findsOneWidget);
  });

  testWidgets('disabled animations keep skeleton content without shimmering',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: AppSkeleton(child: Text('Loading row')),
      ),
    );

    final skeleton = tester.widget<Skeletonizer>(
      find.byWidgetPredicate((widget) => widget is Skeletonizer),
    );
    expect(skeleton.enabled, isTrue);
    expect(skeleton.effect, isA<SoldColorEffect>());
    expect(skeleton.effect?.duration, Duration.zero);
    expect(find.text('Loading row'), findsOneWidget);
  });

  testWidgets('loading hides placeholder actions and disabling restores them',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      var calls = 0;
      await pumpDesignSystem(
        tester,
        AppSkeleton(
          child: AppButton(
            label: 'Placeholder action',
            onPressed: () => calls++,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Placeholder action'), findsNothing);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);

      await pumpDesignSystem(
        tester,
        AppSkeleton(
          enabled: false,
          child: AppButton(
            label: 'Placeholder action',
            onPressed: () => calls++,
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(AppButton));
      expect(
        node,
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(calls, 1);
    } finally {
      handle.dispose();
    }
  });
}
