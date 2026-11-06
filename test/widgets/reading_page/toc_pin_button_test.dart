// 目录固定按钮（TocPinButton）的 widget 测试。
//
// 覆盖：
// - 初始未固定：Icons.lock_open + tooltip / semantic label "Pin table of contents"。
// - 点击固定：Icons.lock + tooltip / semantic label "Unpin table of contents"，
//   tocPinnedProvider 变为 true；再次点击回到 false。
// - 连续 5 次快速点击（中间不 pump）：最终落到唯一确定状态，不产生重复 widget
//   或异常。
import 'package:anx_reader/design_system/buttons/app_icon_button.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:anx_reader/widgets/reading_page/toc_pin_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

const _pinLabel = 'Pin table of contents';
const _unpinLabel = 'Unpin table of contents';

Widget _host() {
  return const ProviderScope(
    child: Center(child: TocPinButton()),
  );
}

ProviderContainer _containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(TocPinButton)),
    listen: false,
  );
}

AppIconButton _iconButton(WidgetTester tester) {
  return tester.widget<AppIconButton>(find.byKey(tocPinButtonKey));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts unlocked and exposes the pin tooltip and semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpDesignSystem(tester, _host());

      expect(_containerOf(tester).read(tocPinnedProvider), isFalse);
      expect(
        find.descendant(
          of: find.byKey(tocPinButtonKey),
          matching: find.byIcon(Icons.lock_open),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock), findsNothing);

      final button = _iconButton(tester);
      expect(button.tooltip, _pinLabel);
      expect(button.semanticLabel, _pinLabel);
      expect(find.byTooltip(_pinLabel), findsOneWidget);
      expect(find.bySemanticsLabel(_pinLabel), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping pins and unpins with icon, label and provider in sync',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpDesignSystem(tester, _host());
      final container = _containerOf(tester);
      expect(container.read(tocPinnedProvider), isFalse);

      await tester.tap(find.byKey(tocPinButtonKey));
      await tester.pump();

      expect(container.read(tocPinnedProvider), isTrue);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsNothing);
      expect(_iconButton(tester).tooltip, _unpinLabel);
      expect(_iconButton(tester).semanticLabel, _unpinLabel);
      expect(find.byTooltip(_unpinLabel), findsOneWidget);
      expect(find.bySemanticsLabel(_unpinLabel), findsWidgets);

      await tester.tap(find.byKey(tocPinButtonKey));
      await tester.pump();

      expect(container.read(tocPinnedProvider), isFalse);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(_iconButton(tester).tooltip, _pinLabel);
      expect(_iconButton(tester).semanticLabel, _pinLabel);
      expect(find.byTooltip(_pinLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('five rapid taps without pumping settle on one deterministic state',
      (tester) async {
    await pumpDesignSystem(tester, _host());
    final container = _containerOf(tester);
    expect(container.read(tocPinnedProvider), isFalse);

    // 中间不 pump：每次 onPressed 都同步 toggle 一次 provider。
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(tocPinButtonKey));
    }
    await tester.pump();

    // 5 次 toggle（奇数）=> 固定状态为 true，且只保留一个按钮 / 一个图标。
    expect(container.read(tocPinnedProvider), isTrue);
    expect(find.byType(TocPinButton), findsOneWidget);
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsNothing);
    expect(_iconButton(tester).tooltip, _unpinLabel);
    expect(tester.takeException(), isNull);

    // 再快速点一次（第 6 次，偶数）=> 回到未固定。
    await tester.tap(find.byKey(tocPinButtonKey));
    await tester.pump();

    expect(container.read(tocPinnedProvider), isFalse);
    expect(find.byType(TocPinButton), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
