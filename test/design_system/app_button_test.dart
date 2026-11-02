import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppButton', () {
    testWidgets(
        'resolves default, pressed, hovered, focused and disabled styles',
        (tester) async {
      for (final variant in AppButtonVariant.values) {
        await pumpDesignSystem(
          tester,
          AppButton(
            label: 'Continue',
            variant: variant,
            onPressed: () {},
          ),
        );

        final style = _buttonStyle(tester, variant);
        final colors =
            Theme.of(tester.element(find.byType(AppButton))).colorScheme;
        final states = <Set<WidgetState>>[
          <WidgetState>{WidgetState.pressed},
          <WidgetState>{WidgetState.hovered},
          <WidgetState>{WidgetState.focused},
        ];
        final defaultOverlay = style.overlayColor!.resolve(<WidgetState>{});
        for (final state in states) {
          expect(
            style.overlayColor!.resolve(state),
            isNot(defaultOverlay),
            reason: '$variant must visibly respond to $state',
          );
        }
        expect(
          style.side!.resolve(<WidgetState>{WidgetState.focused}),
          isNot(style.side!.resolve(<WidgetState>{})),
          reason: '$variant must show a distinct focus border',
        );

        const disabled = <WidgetState>{WidgetState.disabled};
        final expectedDisabledBackground = switch (variant) {
          AppButtonVariant.outlined ||
          AppButtonVariant.text ||
          AppButtonVariant.neutral =>
            colors.surface.withValues(alpha: 0),
          _ => colors.onSurface.withValues(alpha: 0.12),
        };
        expect(
          style.backgroundColor!.resolve(disabled),
          expectedDisabledBackground,
          reason: '$variant must use its disabled background',
        );
        expect(
          style.foregroundColor!.resolve(disabled),
          colors.onSurface.withValues(alpha: 0.38),
          reason: '$variant must use the disabled foreground',
        );
      }
    });

    testWidgets('neutral variant uses onSurfaceVariant on a transparent base',
        (tester) async {
      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Later',
          variant: AppButtonVariant.neutral,
          onPressed: () {},
        ),
      );

      final style = _buttonStyle(tester, AppButtonVariant.neutral);
      final colors =
          Theme.of(tester.element(find.byType(AppButton))).colorScheme;
      expect(
        style.foregroundColor!.resolve(<WidgetState>{}),
        colors.onSurfaceVariant,
      );
      expect(
        style.backgroundColor!.resolve(<WidgetState>{}),
        colors.surface.withValues(alpha: 0),
      );
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('loading is a distinct state and disables tap and long press',
        (tester) async {
      var taps = 0;
      var longPresses = 0;
      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Save',
          isLoading: true,
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      await tester.longPress(find.byType(AppButton));
      expect(taps, 0);
      expect(longPresses, 0);

      final loadingStyle = _buttonStyle(tester, AppButtonVariant.primary);
      final loadingColor = loadingStyle.backgroundColor?.resolve(
        <WidgetState>{WidgetState.disabled},
      );
      await pumpDesignSystem(
        tester,
        AppButton(label: 'Save', enabled: false, onPressed: () {}),
      );
      final disabledColor = _buttonStyle(tester, AppButtonVariant.primary)
          .backgroundColor
          ?.resolve(<WidgetState>{WidgetState.disabled});
      expect(loadingColor, isNot(disabledColor));
    });

    testWidgets('disabled button disables tap and long press', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Save',
          enabled: false,
          onPressed: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      await tester.tap(find.byType(AppButton));
      await tester.longPress(find.byType(AppButton));
      expect(taps, 0);
      expect(longPresses, 0);
    });

    testWidgets('all sizes keep a minimum 48dp touch target', (tester) async {
      for (final size in AppButtonSize.values) {
        await pumpDesignSystem(
          tester,
          AppButton(label: 'A', size: size, onPressed: () {}),
        );
        final bounds = tester.getSize(find.byType(AppButton));
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('supports an icon and a semantic label at 1.3 text scale',
        (tester) async {
      await pumpDesignSystem(
        tester,
        AppButton(
          label: 'Synchronize library',
          icon: Icons.sync,
          semanticLabel: 'Synchronize all books',
          onPressed: () {},
        ),
        textScaler: const TextScaler.linear(1.3),
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.bySemanticsLabel('Synchronize all books'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long multiline label fits narrow icon button and native tap',
        (tester) async {
      var taps = 0;
      const label = 'Synchronize the complete library with safe retry';
      await pumpDesignSystem(
        tester,
        SizedBox(
          width: 180,
          child: AppButton(
            label: label,
            icon: Icons.sync,
            semanticLabel: label,
            onPressed: () => taps++,
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );

      expect(find.text(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long loading label fits and remains disabled at 1.3 scale',
        (tester) async {
      var taps = 0;
      const label = 'Synchronizing all books and downloading remote changes';
      await pumpDesignSystem(
        tester,
        SizedBox(
          width: 180,
          child: AppButton(
            label: label,
            icon: Icons.sync,
            semanticLabel: label,
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

ButtonStyle _buttonStyle(WidgetTester tester, AppButtonVariant variant) {
  return switch (variant) {
    AppButtonVariant.primary ||
    AppButtonVariant.secondary ||
    AppButtonVariant.danger =>
      tester.widget<FilledButton>(find.byType(FilledButton)).style!,
    AppButtonVariant.outlined =>
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!,
    AppButtonVariant.text ||
    AppButtonVariant.neutral =>
      tester.widget<TextButton>(find.byType(TextButton)).style!,
  };
}
