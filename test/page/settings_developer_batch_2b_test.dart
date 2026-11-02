import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/developer/vibration_test_page.dart';
import 'package:anx_reader/service/vibration_service.dart';
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

  testWidgets('capability refresh deduplicates while pending', (tester) async {
    final pending = Completer<VibrationCapabilities>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      VibrationTestPage(
        loadCapabilities: () {
          attempts++;
          if (attempts == 1) return Future.value(_capabilities);
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Refresh capabilities'));
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh capabilities'));
    await tester.pump();

    expect(attempts, 2);
    pending.complete(_capabilities);
    await tester.pumpAndSettle();
  });

  testWidgets('vibration trigger deduplicates while pending', (tester) async {
    final pending = Completer<void>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      VibrationTestPage(
        loadCapabilities: () async => _capabilities,
        vibrate: (_) {
          attempts++;
          return pending.future;
        },
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Success'));
    await tester.pump();
    await tester.tap(find.text('Success'));
    await tester.pump();

    expect(attempts, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial capability failure retries to data', (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      VibrationTestPage(
        loadCapabilities: () async {
          attempts++;
          if (attempts == 1) throw StateError('private platform error');
          return _capabilities;
        },
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pump();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private platform error'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _capabilities = VibrationCapabilities(
  hasVibrator: true,
  hasAmplitudeControl: true,
  hasCustomVibrationsSupport: true,
  canUseHaptics: true,
);
