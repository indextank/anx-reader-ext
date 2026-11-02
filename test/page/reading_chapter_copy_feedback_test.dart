import 'package:anx_reader/page/reading_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('chapter copy success shows localized success feedback',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ReadingChapterCopyButton(
        contentLoader: () async => 'abc',
        clipboardWriter: (_) async {},
      ),
    );

    await tester.tap(find.byTooltip('Copy chapter content'));
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Copied 3 characters'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('chapter copy failure shows localized error feedback',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ReadingChapterCopyButton(
        contentLoader: () async => throw StateError('private copy failure'),
      ),
    );

    await tester.tap(find.byTooltip('Copy chapter content'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Error copying content'), findsOneWidget);
    expect(find.textContaining('private copy failure'), findsNothing);
  });
}
