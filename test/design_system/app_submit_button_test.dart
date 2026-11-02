import 'dart:async';

import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/buttons/app_submit_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppSubmitButton', () {
    testWidgets(
        'a Completer-controlled submission only runs once while pending',
        (tester) async {
      final completer = Completer<void>();
      var calls = 0;
      await pumpDesignSystem(
        tester,
        AppSubmitButton(
          label: 'Save changes',
          onSubmit: () {
            calls++;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await tester.tap(find.byType(AppSubmitButton));
      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();
      expect(calls, 1);

      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('failure shows a recoverable localized error and can retry',
        (tester) async {
      var attempts = 0;
      await pumpDesignSystem(
        tester,
        AppSubmitButton(
          label: 'Save changes',
          onSubmit: () async {
            attempts++;
            if (attempts == 1) throw StateError('private failure details');
          },
        ),
      );

      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Action failed. Try again.'), findsOneWidget);
      expect(find.textContaining('private failure details'), findsNothing);
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('external loading and disabled values block submission',
        (tester) async {
      var calls = 0;
      for (final state in <(bool, bool)>[(true, false), (false, true)]) {
        await pumpDesignSystem(
          tester,
          AppSubmitButton(
            label: 'Submit',
            disabled: state.$1,
            isLoading: state.$2,
            onSubmit: () async => calls++,
          ),
        );
        await tester.tap(find.byType(AppSubmitButton));
        await tester.pump();
      }
      expect(calls, 0);
    });

    testWidgets('completion after dispose does not set state', (tester) async {
      final completer = Completer<void>();
      await pumpDesignSystem(
        tester,
        AppSubmitButton(
          label: 'Submit',
          onSubmit: () => completer.future,
        ),
      );
      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();

      await pumpDesignSystem(tester, const SizedBox.shrink());
      completer.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps AppButton variants and a 48dp target', (tester) async {
      await pumpDesignSystem(
        tester,
        AppSubmitButton(
          label: 'Delete',
          variant: AppButtonVariant.danger,
          onSubmit: () async {},
        ),
      );
      final size = tester.getSize(find.byType(AppSubmitButton));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('inline feedback mode avoids a global SnackBar on retry',
        (tester) async {
      var attempts = 0;
      await pumpDesignSystem(
        tester,
        AppSubmitButton(
          label: 'Save changes',
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: () async {
            attempts++;
            if (attempts == 1) throw StateError('private failure');
          },
        ),
      );

      await tester.tap(find.byType(AppSubmitButton));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Action failed. Try again.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
