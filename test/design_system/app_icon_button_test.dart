import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/buttons/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppIconButton', () {
    testWidgets('resolves all five interaction states', (tester) async {
      await pumpDesignSystem(
        tester,
        AppIconButton(
          icon: Icons.more_vert,
          tooltip: 'More actions',
          variant: AppButtonVariant.outlined,
          onPressed: () {},
        ),
      );

      final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
      final colors =
          Theme.of(tester.element(find.byType(AppIconButton))).colorScheme;
      final defaultOverlay = style.overlayColor!.resolve(<WidgetState>{});
      for (final state in <Set<WidgetState>>[
        <WidgetState>{WidgetState.pressed},
        <WidgetState>{WidgetState.hovered},
        <WidgetState>{WidgetState.focused},
      ]) {
        expect(style.overlayColor!.resolve(state), isNot(defaultOverlay));
      }
      expect(
        style.side!.resolve(<WidgetState>{WidgetState.focused}),
        isNot(style.side!.resolve(<WidgetState>{})),
      );
      const disabled = <WidgetState>{WidgetState.disabled};
      expect(
        style.backgroundColor!.resolve(disabled),
        colors.surface.withValues(alpha: 0),
      );
      expect(
        style.foregroundColor!.resolve(disabled),
        colors.onSurface.withValues(alpha: 0.38),
      );
    });

    testWidgets('neutral variant paints the icon with onSurfaceVariant',
        (tester) async {
      await pumpDesignSystem(
        tester,
        AppIconButton(
          icon: Icons.close,
          tooltip: 'Close',
          variant: AppButtonVariant.neutral,
          onPressed: () {},
        ),
      );

      final colors =
          Theme.of(tester.element(find.byType(AppIconButton))).colorScheme;
      final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
      expect(
        style.foregroundColor!.resolve(<WidgetState>{}),
        colors.onSurfaceVariant,
      );
      expect(
        style.backgroundColor!.resolve(<WidgetState>{}),
        colors.surface.withValues(alpha: 0),
      );
      // 图标实际拿到的前景色（IconButton 通过 IconTheme 下发）。
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.close))).color,
        colors.onSurfaceVariant,
      );
    });

    testWidgets('keeps a 48dp target and exposes tooltip and semantics',
        (tester) async {
      await pumpDesignSystem(
        tester,
        AppIconButton(
          icon: Icons.more_vert,
          tooltip: 'More actions',
          semanticLabel: 'Open book actions',
          onPressed: () {},
        ),
      );

      final size = tester.getSize(find.byType(AppIconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Open book actions'), findsOneWidget);

      await tester.longPress(find.byType(AppIconButton));
      await tester.pumpAndSettle();
      expect(find.text('More actions'), findsOneWidget);
    });

    testWidgets('loading and disabled states reject tap and long press',
        (tester) async {
      var calls = 0;
      for (final isLoading in <bool>[false, true]) {
        await pumpDesignSystem(
          tester,
          AppIconButton(
            icon: Icons.delete_outline,
            enabled: isLoading,
            isLoading: isLoading,
            tooltip: 'Delete',
            onPressed: () => calls++,
            onLongPress: () => calls++,
          ),
        );
        await tester.tap(find.byType(AppIconButton));
        await tester.longPress(find.byType(AppIconButton));
      }
      expect(calls, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
