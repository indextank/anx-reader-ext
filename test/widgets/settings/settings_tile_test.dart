import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('settings section and switch tile adapt to 1.3 text scale',
      (tester) async {
    var value = false;
    await pumpDesignSystem(
      tester,
      SizedBox(
        width: 300,
        child: ListView(
          children: [
            SettingsSection(
              title: const Text('Reading and synchronization preferences'),
              tiles: [
                SettingsTile.switchTile(
                  initialValue: value,
                  leading: const Icon(Icons.sync),
                  title: const Text(
                    'Synchronize reading progress across every device',
                  ),
                  description: const Text(
                    'Changes are stored with the existing preference behavior.',
                  ),
                  onToggle: (newValue) => value = newValue,
                ),
              ],
            ),
          ],
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.byType(ListTile));
    expect(value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled tile does not invoke actions', (tester) async {
    var calls = 0;
    await pumpDesignSystem(
      tester,
      SettingsTile.navigation(
        enabled: false,
        title: const Text('Unavailable'),
        onPressed: (_) => calls++,
      ),
    );

    await tester.tap(find.byType(ListTile));
    expect(calls, 0);
  });
}
