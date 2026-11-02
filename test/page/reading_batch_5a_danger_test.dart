import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('deleting a reading theme requires design system confirmation',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ThemeChangeWidget(
        readTheme: ReadTheme(
          id: 1,
          backgroundColor: 'ff121212',
          textColor: 'ffcccccc',
          backgroundImagePath: '',
        ),
        setCurrentPage: (_) {},
      ),
    );

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Delete'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
