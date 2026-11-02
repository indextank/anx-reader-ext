import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/buttons/app_icon_button.dart';
import 'package:anx_reader/design_system/layout/app_card.dart';
import 'package:anx_reader/design_system/layout/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('AppButton replaces only its content label and preserves actions',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      var taps = 0;
      var longPresses = 0;
      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Save',
          semanticLabel: 'Save all changes',
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      final node = tester.getSemantics(find.byType(AppButton));
      expect(
        node,
        matchesSemantics(
          label: 'Save all changes',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.longPress,
      );
      await tester.pump();
      expect(taps, 1);
      expect(longPresses, 1);

      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Save',
          semanticLabel: 'Saving is unavailable',
          enabled: false,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(AppButton)),
        matchesSemantics(
          label: 'Saving is unavailable',
          isButton: true,
          hasEnabledState: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('AppIconButton keeps native button actions and enabled state',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpDesignSystem(
        tester,
        AppIconButton(
          icon: Icons.delete_outline,
          semanticLabel: 'Delete selected book',
          onPressed: () {},
          onLongPress: () {},
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppIconButton)),
        matchesSemantics(
          label: 'Delete selected book',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('AppCard keeps tap and long press semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpDesignSystem(
        tester,
        AppCard(
          semanticLabel: 'Open selected book',
          onTap: () {},
          onLongPress: () {},
          child: const Text('Book'),
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppCard)),
        matchesSemantics(
          label: 'Open selected book',
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('AppListTile preserves selected, enabled and gesture states',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpDesignSystem(
        tester,
        AppListTile(
          title: 'Reading settings',
          subtitle: 'Current page',
          semanticLabel: 'Selected reading settings',
          selected: true,
          onTap: () {},
          onLongPress: () {},
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppListTile)),
        matchesSemantics(
          label: 'Selected reading settings',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });
}
