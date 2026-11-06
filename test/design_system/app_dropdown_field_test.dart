import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_dropdown_tokens.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  test('global dropdown option height is smaller than Material default', () {
    expect(AppDropdownTokens.itemHeight, lessThan(48));
    final theme = AppTheme.build(
      brightness: Brightness.light,
      seedColor: AppColors.defaultBrand,
    );
    final minimumSize =
        theme.menuButtonTheme.style?.minimumSize?.resolve(<WidgetState>{});
    expect(minimumSize, isNotNull);
    expect(minimumSize!.height, AppDropdownTokens.itemHeight);
    final darkTheme = AppTheme.build(
      brightness: Brightness.dark,
      seedColor: AppColors.defaultBrand,
    );
    expect(
      darkTheme.menuButtonTheme.style?.minimumSize
          ?.resolve(<WidgetState>{})?.height,
      AppDropdownTokens.itemHeight,
    );
  });

  testWidgets('DropdownMenu options use the global reduced height',
      (tester) async {
    await pumpDesignSystem(
      tester,
      Center(
        child: DropdownMenu<String>(
          initialSelection: 'a',
          dropdownMenuEntries: const <DropdownMenuEntry<String>>[
            DropdownMenuEntry<String>(value: 'a', label: 'Option A'),
            DropdownMenuEntry<String>(value: 'b', label: 'Option B'),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    final items = find.byType(MenuItemButton);
    expect(items, findsWidgets);
    for (var i = 0; i < items.evaluate().length; i++) {
      expect(
        tester.getSize(items.at(i)).height,
        AppDropdownTokens.itemHeight,
        reason: '全局 DropdownMenu 选项高度应为 ${AppDropdownTokens.itemHeight}',
      );
    }
  });

  testWidgets('AppDropdownField uses the reduced height and stays functional',
      (tester) async {
    String? selected = 'a';
    await pumpDesignSystem(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Center(
          child: AppDropdownField<String>(
            value: selected,
            items: const <AppDropdownItem<String>>[
              AppDropdownItem<String>(value: 'a', label: 'Option A'),
              AppDropdownItem<String>(value: 'b', label: 'Option B'),
            ],
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppDropdownField<String>));
    await tester.pumpAndSettle();
    final items = find.byType(MenuItemButton);
    expect(items, findsWidgets);
    for (var i = 0; i < items.evaluate().length; i++) {
      expect(tester.getSize(items.at(i)).height, AppDropdownTokens.itemHeight);
    }
    await tester.tap(find.text('Option B').last);
    await tester.pumpAndSettle();
    expect(selected, 'b');
    expect(tester.takeException(), isNull);
  });
}
