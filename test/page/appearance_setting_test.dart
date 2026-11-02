import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('appearance switches still update Riverpod at 1.3 scale',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpDesignSystem(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: const AppearanceSetting(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(container.read(uiSettingsProvider).trueDarkMode, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color save failure stays in the dialog and retries successfully',
      (tester) async {
    final notifier = _FailingThemeColorSettings();
    final container = ProviderContainer(
      overrides: [uiSettingsProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);

    await pumpDesignSystem(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: const AppearanceSetting(),
      ),
    );

    await tester.tap(find.text('Theme Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    expect(notifier.attempts, 1);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Action failed. Try again.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Retry'),
    ));
    await tester.pumpAndSettle();

    expect(notifier.attempts, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FailingThemeColorSettings extends UiSettings {
  var attempts = 0;

  @override
  Future<void> setThemeColor(Color value) async {
    attempts++;
    if (attempts == 1) throw StateError('private theme write failure');
    await super.setThemeColor(value);
  }
}
