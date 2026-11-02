import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/feedback/app_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('desktop Overlay toast works without native platform channels',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpDesignSystem(
      tester,
      Column(
        children: [
          Builder(
            builder: (context) => AppButton(
              label: 'Show success',
              onPressed: () => AppFeedback.showSuccess(context),
            ),
          ),
          Builder(
            builder: (context) => AppButton(
              label: 'Show information',
              onPressed: () => AppFeedback.showInfo(
                context,
                message: 'Library is already up to date.',
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Show success'));
    await tester.pump();
    expect(find.text('Success'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('Show information'));
    await tester.pump();
    expect(find.text('Success'), findsNothing);
    expect(find.text('Library is already up to date.'), findsOneWidget);

    await pumpDesignSystem(tester, const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Library is already up to date.'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
