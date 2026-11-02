import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/home_page/settings_page.dart';
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

  testWidgets('internally created scroll controller is disposed with the page',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: SettingsPage()),
    );
    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;

    await pumpDesignSystem(tester, const SizedBox.shrink());

    expect(
      () => controller.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('externally supplied scroll controller remains caller-owned',
      (tester) async {
    final controller = _TrackingScrollController();
    addTearDown(controller.dispose);
    await pumpDesignSystem(
      tester,
      ProviderScope(child: SettingsPage(controller: controller)),
    );

    await pumpDesignSystem(tester, const SizedBox.shrink());

    expect(controller.disposed, isFalse);
  });

  testWidgets('null to external disposes only the old internal controller',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: SettingsPage()),
    );
    final internal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    final external = _TrackingScrollController();
    addTearDown(external.dispose);

    await pumpDesignSystem(
      tester,
      ProviderScope(child: SettingsPage(controller: external)),
    );

    expect(
      () => internal.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller,
      same(external),
    );

    await pumpDesignSystem(tester, const SizedBox.shrink());
    expect(external.disposed, isFalse);
  });

  testWidgets('external to null creates and owns a new internal controller',
      (tester) async {
    final external = _TrackingScrollController();
    addTearDown(external.dispose);
    await pumpDesignSystem(
      tester,
      ProviderScope(child: SettingsPage(controller: external)),
    );

    await pumpDesignSystem(
      tester,
      const ProviderScope(child: SettingsPage()),
    );
    final internal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;

    expect(internal, isNot(same(external)));
    expect(external.disposed, isFalse);

    await pumpDesignSystem(tester, const SizedBox.shrink());
    expect(
      () => internal.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
    expect(external.disposed, isFalse);
  });
}

class _TrackingScrollController extends ScrollController {
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
