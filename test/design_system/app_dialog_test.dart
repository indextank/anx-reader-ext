import 'dart:async';

import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/feedback/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppDialog', () {
    testWidgets('danger confirmation requires and shows a danger explanation',
        (tester) async {
      Object? validationError;
      await pumpDesignSystem(
        tester,
        _ConfirmationLauncher(
          isDangerous: true,
          dangerDescription: null,
          onError: (error) => validationError = error,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      expect(validationError, isA<ArgumentError>());
      expect(find.byType(AlertDialog), findsNothing);

      await pumpDesignSystem(
        tester,
        const _ConfirmationLauncher(
          isDangerous: true,
          dangerDescription: 'This permanently deletes all local reading data.',
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete reading data'), findsOneWidget);
      expect(
        find.text('This permanently deletes all local reading data.'),
        findsOneWidget,
      );
      final confirm = tester.widget<AppButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(AppButton),
        ),
      );
      expect(confirm.variant, AppButtonVariant.danger);
    });

    testWidgets('async confirm is pending, deduplicated and closes on success',
        (tester) async {
      final completer = Completer<void>();
      var calls = 0;
      bool? result;
      await pumpDesignSystem(
        tester,
        _ConfirmationLauncher(
          isDangerous: true,
          dangerDescription: 'This action cannot be undone.',
          onConfirm: () {
            calls++;
            return completer.future;
          },
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(AlertDialog), findsOneWidget);

      completer.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('cancel returns false and the shell grows at 1.3 text scale',
        (tester) async {
      bool? result;
      await pumpDesignSystem(
        tester,
        _ConfirmationLauncher(
          onResult: (value) => result = value,
        ),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('failed confirm shows inline retry inside the modal',
        (tester) async {
      final retryCompleter = Completer<void>();
      var attempts = 0;
      bool? result;
      await pumpDesignSystem(
        tester,
        _ConfirmationLauncher(
          isDangerous: true,
          dangerDescription: 'This action cannot be undone.',
          onConfirm: () {
            attempts++;
            if (attempts == 1) {
              return Future<void>.error(StateError('private failure'));
            }
            return retryCompleter.future;
          },
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final inlineError = find.text('Action failed. Try again.');
      expect(inlineError, findsOneWidget);
      expect(
        find.ancestor(
          of: inlineError,
          matching: find.byType(AlertDialog),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private failure'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(attempts, 2);

      retryCompleter.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

class _ConfirmationLauncher extends StatelessWidget {
  const _ConfirmationLauncher({
    this.isDangerous = false,
    this.dangerDescription,
    this.onConfirm,
    this.onResult,
    this.onError,
  });

  final bool isDangerous;
  final String? dangerDescription;
  final Future<void> Function()? onConfirm;
  final ValueChanged<bool>? onResult;
  final ValueChanged<Object>? onError;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Open dialog',
      onPressed: () {
        try {
          AppDialog.confirm(
            context,
            title: isDangerous ? 'Delete reading data' : 'Leave this page',
            message: isDangerous
                ? 'Delete the selected reading data?'
                : 'Discard unsaved changes?',
            confirmLabel: isDangerous ? 'Delete' : null,
            isDangerous: isDangerous,
            dangerDescription: dangerDescription,
            onConfirm: onConfirm,
          ).then((value) => onResult?.call(value));
        } catch (error) {
          onError?.call(error);
        }
      },
    );
  }
}
