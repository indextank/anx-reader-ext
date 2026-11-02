import 'package:anx_reader/design_system/layout/app_safe_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets(
      'AppSafeArea combines padding and keyboard insets without doubling',
      (tester) async {
    const childKey = ValueKey('safe-area-child');
    await pumpDesignSystem(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(left: 8, top: 12, right: 8, bottom: 20),
          viewInsets: EdgeInsets.only(bottom: 100),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: AppSafeArea(
            child: SizedBox(key: childKey, width: 10, height: 10),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(childKey)), const Offset(8, 12));
    expect(tester.getSize(find.byType(AppSafeArea)), const Size(26, 122));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSafeArea can opt out of keyboard avoidance', (tester) async {
    const childKey = ValueKey('safe-area-child');
    await pumpDesignSystem(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 20),
          viewInsets: EdgeInsets.only(bottom: 100),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: AppSafeArea(
            avoidViewInsets: false,
            child: SizedBox(key: childKey, width: 10, height: 10),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppSafeArea)), const Size(10, 30));
  });
}
