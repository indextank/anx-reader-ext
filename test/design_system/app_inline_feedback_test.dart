import 'dart:async';

import 'package:anx_reader/design_system/feedback/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('inline retry is pending and deduplicated', (tester) async {
    final firstAttempt = Completer<void>();
    var attempts = 0;

    await pumpDesignSystem(
      tester,
      AppInlineFeedback(
        onRetry: () async {
          attempts++;
          if (attempts == 1) await firstAttempt.future;
        },
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(attempts, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    firstAttempt.complete();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
  });

  testWidgets('failed inline retry is contained and remains usable',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      AppInlineFeedback(
        onRetry: () async {
          attempts++;
          if (attempts == 1) throw StateError('private retry details');
        },
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('private retry details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
