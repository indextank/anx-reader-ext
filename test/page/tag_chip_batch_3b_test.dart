import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/common/tag_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('tag rename deduplicates and keeps failed draft at 1.3x',
      (tester) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var calls = 0;
    await _pumpTagEditor(
      tester,
      onRename: (name) {
        calls++;
        if (calls == 1) return firstAttempt.future;
        return retryAttempt.future;
      },
    );

    await tester.tap(find.text('Open'));
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField), 'Renamed tag');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 1);

    firstAttempt.completeError(StateError('private rename failure'));
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.text('Renamed tag'), findsOneWidget);
    expect(find.textContaining('private rename failure'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 2);
    retryAttempt.complete();
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag deletion requires design-system confirmation',
      (tester) async {
    var deleteCalls = 0;
    await _pumpTagEditor(
      tester,
      onDelete: () async => deleteCalls++,
    );

    await tester.tap(find.text('Open'));
    await _pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsNWidgets(2));
    expect(deleteCalls, 0);

    await tester.tap(find.widgetWithText(AppButton, 'Delete'));
    await _pumpFrames(tester);

    expect(deleteCalls, 1);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag color failure retries picked color without renaming',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    final attemptedColors = <Color>[];
    var renameCalls = 0;
    await _pumpTagEditor(
      tester,
      onRename: (_) async => renameCalls++,
      onColorChange: (color) {
        attemptedColors.add(color);
        if (attemptedColors.length == 1) return firstAttempt.future;
        return retryAttempt.future;
      },
    );

    await tester.tap(find.text('Open'));
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('Pick tag color'));
    await _pumpFrames(tester);
    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(attemptedColors, hasLength(1));
    await tester.tap(find.byTooltip('Pick tag color'));
    await tester.pump();
    expect(attemptedColors, hasLength(1));

    firstAttempt.completeError(StateError('private color failure'));
    await _pumpFrames(tester);

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(renameCalls, 0);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(attemptedColors, hasLength(2));
    expect(attemptedColors.first, attemptedColors.last);
    expect(renameCalls, 0);

    retryAttempt.complete();
    await _pumpFrames(tester);
    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(renameCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpTagEditor(
  WidgetTester tester, {
  Future<void> Function(String name)? onRename,
  Future<void> Function(Color color)? onColorChange,
  Future<void> Function()? onDelete,
}) async {
  await pumpDesignSystem(
    tester,
    Builder(
      builder: (context) => AppButton(
        label: 'Open',
        onPressed: () {
          TagChip.showEditDialog(
            context: context,
            initialName: 'Original tag',
            initialColor: null,
            onRename: onRename ?? (_) async {},
            onColorChange: onColorChange ?? (_) async {},
            onDelete: onDelete ?? () async {},
          );
        },
      ),
    ),
    textScaler: const TextScaler.linear(1.3),
  );
}
