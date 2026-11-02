import 'package:anx_reader/design_system/layout/app_card.dart';
import 'package:anx_reader/design_system/layout/app_list_tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('AppCard provides interaction and at least a 48dp target',
      (tester) async {
    var taps = 0;
    await pumpDesignSystem(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: AppCard(
          onTap: () => taps++,
          child: const Text('Book'),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AppCard));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(AppCard));
    expect(taps, 1);
  });

  testWidgets('AppCard disabled state removes interactions', (tester) async {
    var calls = 0;
    await pumpDesignSystem(
      tester,
      AppCard(
        enabled: false,
        onTap: () => calls++,
        onLongPress: () => calls++,
        child: const Text('Book'),
      ),
    );
    await tester.tap(find.byType(AppCard));
    await tester.longPress(find.byType(AppCard));
    expect(calls, 0);
  });

  testWidgets('AppCard handles a real secondary mouse button', (tester) async {
    var calls = 0;
    await pumpDesignSystem(
      tester,
      AppCard(
        onSecondaryTap: () => calls++,
        child: const Text('Book'),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppCard)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('AppCard disabled state removes secondary mouse interaction',
      (tester) async {
    var calls = 0;
    await pumpDesignSystem(
      tester,
      AppCard(
        enabled: false,
        onSecondaryTap: () => calls++,
        child: const Text('Book'),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppCard)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('AppListTile keeps content interactive and at least 48dp high',
      (tester) async {
    var taps = 0;
    await pumpDesignSystem(
      tester,
      AppListTile(
        leading: const Icon(Icons.book_outlined),
        title: 'Reading settings',
        subtitle: 'Fonts and pagination',
        trailing: const Icon(Icons.chevron_right),
        onTap: () => taps++,
      ),
    );

    expect(tester.getSize(find.byType(AppListTile)).height,
        greaterThanOrEqualTo(48));
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Fonts and pagination'), findsOneWidget);
    await tester.tap(find.byType(AppListTile));
    expect(taps, 1);
  });

  testWidgets('AppListTile disabled state removes tap and long press',
      (tester) async {
    var calls = 0;
    await pumpDesignSystem(
      tester,
      AppListTile(
        title: 'Unavailable',
        enabled: false,
        onTap: () => calls++,
        onLongPress: () => calls++,
      ),
    );
    await tester.tap(find.byType(AppListTile));
    await tester.longPress(find.byType(AppListTile));
    expect(calls, 0);
  });
}
