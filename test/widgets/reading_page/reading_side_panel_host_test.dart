import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

const _readerKey = ValueKey('host-test-reader');

Widget _hostRow({
  double width = 300,
  double minWidth = 240,
  double maxWidth = 600,
  ValueChanged<double>? onResize,
  VoidCallback? onResizeEnd,
  VoidCallback? onSwitchPosition,
  VoidCallback? onClose,
}) {
  return Row(
    children: [
      const Expanded(child: SizedBox(key: _readerKey)),
      ReadingSidePanelHost(
        width: width,
        minWidth: minWidth,
        maxWidth: maxWidth,
        onResize: onResize ?? (_) {},
        onResizeEnd: onResizeEnd ?? () {},
        onSwitchPosition: onSwitchPosition ?? () {},
        onClose: onClose ?? () {},
        child: const Text('side-panel-content'),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host renders its width, left divider, and content',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDesignSystem(tester, _hostRow());

    expect(tester.getSize(find.byType(ReadingSidePanelHost)).width, 300);
    expect(
      find.descendant(
        of: find.byType(ReadingSidePanelHost),
        matching: find.byType(VerticalDivider),
      ),
      findsOneWidget,
    );
    expect(find.text('side-panel-content'), findsOneWidget);
  });

  testWidgets('host position and close actions each call back once',
      (tester) async {
    var switchCalls = 0;
    var closeCalls = 0;
    await pumpDesignSystem(
      tester,
      _hostRow(
        onSwitchPosition: () => switchCalls++,
        onClose: () => closeCalls++,
      ),
    );

    final host = find.byType(ReadingSidePanelHost);
    final l10n = L10n.of(tester.element(host));
    await tester.tap(
      find.descendant(of: host, matching: find.byTooltip(l10n.aiShowAtBottom)),
    );
    await tester.pump();
    expect(switchCalls, 1);
    expect(closeCalls, 0);

    await tester.tap(
      find.descendant(of: host, matching: find.byTooltip(l10n.close)),
    );
    await tester.pump();
    expect(switchCalls, 1);
    expect(closeCalls, 1);
  });

  testWidgets('left divider reports resize deltas and completion',
      (tester) async {
    final deltas = <double>[];
    var resizeEndCalls = 0;
    await pumpDesignSystem(
      tester,
      _hostRow(
        onResize: deltas.add,
        onResizeEnd: () => resizeEndCalls++,
      ),
    );

    await tester.drag(find.byType(VerticalDivider), const Offset(-40, 0));
    await tester.pump();

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((total, delta) => total + delta), -40);
    expect(resizeEndCalls, 1);
  });

  testWidgets('host remains bounded on a narrow short screen', (tester) async {
    tester.view.physicalSize = const Size(200, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDesignSystem(tester, _hostRow());

    expect(tester.getSize(find.byType(ReadingSidePanelHost)).width, 200);
    expect(tester.getSize(find.byKey(_readerKey)).width, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host clamps to the available width so reader can reach zero',
      (tester) async {
    tester.view.physicalSize = const Size(200, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDesignSystem(tester, _hostRow());

    expect(tester.getSize(find.byType(ReadingSidePanelHost)).width, 200);
    expect(tester.getSize(find.byKey(_readerKey)).width, 0);
    expect(tester.takeException(), isNull);
  });
}
