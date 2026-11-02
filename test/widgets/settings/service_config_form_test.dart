import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('editing in the middle preserves the text selection',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ServiceConfigForm(
        configItems: [
          ConfigItem(key: 'server', label: 'Server', type: ConfigItemType.text),
        ],
        initialConfig: const {'server': 'abcdef'},
        onConfigChanged: (_) {},
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abXdef',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'abXdef');
    expect(field.controller!.selection.baseOffset, 3);
  });

  testWidgets('range configuration wraps instead of overflowing at 1.3 scale',
      (tester) async {
    await pumpDesignSystem(
      tester,
      SizedBox(
        width: 260,
        child: ServiceConfigForm(
          configItems: [
            ConfigItem(
              key: 'timeout',
              label: 'Connection timeout with a descriptive label',
              description: 'Choose how long the service waits before stopping.',
              type: ConfigItemType.range,
              defaultValue: 30,
              min: 0,
              max: 100,
              unit: ' seconds',
            ),
          ],
          initialConfig: const {},
          onConfigChanged: (_) {},
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.text('30 seconds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password visibility keeps icons and semantics in sync',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ServiceConfigForm(
        configItems: [
          ConfigItem(
            key: 'password',
            label: 'Password',
            type: ConfigItemType.password,
          ),
        ],
        initialConfig: const {'password': 'secret'},
        onConfigChanged: (_) {},
      ),
    );

    IconButton button() => tester.widget<IconButton>(find.byType(IconButton));
    TextField field() => tester.widget<TextField>(find.byType(TextField));

    expect(field().obscureText, isTrue);
    expect(button().tooltip, 'Show password');
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(field().obscureText, isFalse);
    expect(button().tooltip, 'Hide password');
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(field().obscureText, isTrue);
    expect(button().tooltip, 'Show password');
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });
}
