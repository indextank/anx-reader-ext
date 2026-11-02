import 'dart:async';

import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('tag apply requires confirmation and can recover from failure',
      (tester) async {
    final retryAttempt = Completer<void>();
    var calls = 0;
    await pumpDesignSystem(
      tester,
      SingleChildScrollView(
        child: ApplyBookTagsStepTile(
          step: _step,
          applyPlan: (plan) {
            calls++;
            expect(plan['books'], isEmpty);
            if (calls == 1) {
              return Future<void>.error(StateError('private tag details'));
            }
            return retryAttempt.future;
          },
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private tag details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, 2);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    retryAttempt.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Applied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

const _step = ParsedToolStep(
  name: 'apply_book_tags',
  status: 'success',
  output:
      '{"status":"ok","data":{"requiresConfirmation":true,"plan":{"books":[],"mergeTags":[],"updateTags":[],"createTags":[],"bookChanges":[]},"conflicts":[]}}',
);
