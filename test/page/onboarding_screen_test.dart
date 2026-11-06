import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/onboarding_screen.dart';
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

  testWidgets('appearance onboarding keeps Riverpod behavior at 1.3 scale',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var completed = 0;

    await pumpDesignSystem(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: OnboardingScreen(onComplete: () => completed++),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.text('Skip'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AppDropdownField<String>), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.byType(Switch)),
      alignment: 0.5,
    );
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(container.read(uiSettingsProvider).eInkMode, isTrue);
    expect(completed, 0);
    expect(tester.takeException(), isNull);
  });
}
