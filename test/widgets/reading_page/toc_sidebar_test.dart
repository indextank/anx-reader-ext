// 固定目录侧栏宽度解析（resolveTocSidebarWidth）与 TocSidebar widget 测试。
//
// 覆盖：
// - 宽屏（>= 840）固定 320；
// - 窄屏按 0.32 比例取值，先夹在 [200, 320]，再被 45% 可用宽度封顶：
//   600 -> 200，400 -> 180，360 -> 162；839 仍未到宽屏断点；
// - 0 / 负数 / NaN / 无穷 => 0；
// - 1..2000 全量属性断言：结果 >= 0、<= 45%、<= 固定宽度；
// - widget：Row（侧栏 + Expanded 正文）在 360x640 / 240x400 下渲染，
//   Key 存在、正文可见、侧栏占满可用高度、无异常。
import 'package:anx_reader/widgets/reading_page/toc_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

Widget _host(Size size) {
  final availableWidth = size.width;
  return SizedBox(
    width: availableWidth,
    height: size.height,
    child: Row(
      children: [
        TocSidebar(
          width: resolveTocSidebarWidth(availableWidth),
          child: const Text('toc'),
        ),
        const Expanded(child: Text('reader')),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveTocSidebarWidth', () {
    test('wide screens use the fixed 320 logical pixel sidebar', () {
      expect(tocSidebarFixedWidth, 320);
      expect(tocSidebarWideBreakpoint, 840);

      expect(resolveTocSidebarWidth(1000), 320);
      expect(resolveTocSidebarWidth(1440), 320);
      expect(resolveTocSidebarWidth(1920), 320);

      // 宽屏断点及以上（含 840/999）统一固定 320，并由 45% 上限封顶。
      expect(resolveTocSidebarWidth(840), 320);
      expect(resolveTocSidebarWidth(999), 320);
      expect(resolveTocSidebarWidth(1000), 320);
    });

    test('narrow screens take 0.32 of the width clamped then capped at 45%', () {
      expect(tocSidebarMinWidth, 200);
      expect(tocSidebarNarrowFraction, 0.32);
      expect(tocSidebarMaxScreenFraction, 0.45);

      // 600 * 0.32 = 192 -> 最小宽度 200；45% 上限 = 270 => 200。
      expect(resolveTocSidebarWidth(600), 200);

      // 400 * 0.32 = 128 -> 最小宽度 200；45% 上限 = 180 => 180。
      expect(resolveTocSidebarWidth(400), closeTo(180.0, 1e-9));

      // 360 * 0.32 = 115.2 -> 最小宽度 200；45% 上限 = 162 => 162。
      expect(resolveTocSidebarWidth(360), closeTo(162.0, 1e-9));

      // 240 * 0.32 = 76.8 -> 最小宽度 200；45% 上限 = 108 => 108。
      expect(resolveTocSidebarWidth(240), closeTo(108.0, 1e-9));

      // 比例值在 [200, 320] 内时直接使用比例值（且未触发 45% 上限）。
      expect(resolveTocSidebarWidth(700), closeTo(224.0, 1e-9));
      expect(resolveTocSidebarWidth(800), closeTo(256.0, 1e-9));

      // 宽屏断点前一个像素仍然走比例分支。
      expect(resolveTocSidebarWidth(839), closeTo(839 * 0.32, 1e-9));
    });

    test('non-positive and non-finite widths resolve to zero', () {
      expect(resolveTocSidebarWidth(0), 0);
      expect(resolveTocSidebarWidth(-1), 0);
      expect(resolveTocSidebarWidth(-0.5), 0);
      expect(resolveTocSidebarWidth(double.infinity), 0);
      expect(resolveTocSidebarWidth(double.negativeInfinity), 0);
      expect(resolveTocSidebarWidth(double.nan), 0);
    });

    test('never exceeds 45% of the available width for widths 1..2000', () {
      for (var width = 1.0; width <= 2000; width += 1) {
        final resolved = resolveTocSidebarWidth(width);
        expect(resolved, greaterThanOrEqualTo(0), reason: 'width=$width');
        expect(
          resolved,
          lessThanOrEqualTo(width * tocSidebarMaxScreenFraction + 1e-9),
          reason: 'width=$width 必须给正文留出 >= 55%',
        );
        expect(
          resolved,
          lessThanOrEqualTo(width),
          reason: 'width=$width 不得超过可用宽度',
        );
        expect(
          resolved,
          lessThanOrEqualTo(tocSidebarFixedWidth),
          reason: 'width=$width 不得超过固定宽度',
        );
      }
    });
  });

  group('TocSidebar widget', () {
    testWidgets('renders at 360x640 with 162px sidebar and full height',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpDesignSystem(tester, _host(const Size(360, 640)));

      final sidebar = find.byKey(tocPinnedSidebarKey);
      expect(sidebar, findsOneWidget);

      final sidebarSize = tester.getSize(sidebar);
      expect(sidebarSize.width, closeTo(162.0, 1e-6));
      // 侧栏必须填满可用高度（CrossAxisAlignment.stretch 生效）。
      expect(sidebarSize.height, 640);
      expect(find.text('toc'), findsOneWidget);
      expect(find.text('reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays bounded at a narrow 240x400 viewport', (tester) async {
      tester.view.physicalSize = const Size(240, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpDesignSystem(tester, _host(const Size(240, 400)));

      final sidebar = find.byKey(tocPinnedSidebarKey);
      expect(sidebar, findsOneWidget);

      final sidebarSize = tester.getSize(sidebar);
      expect(sidebarSize.width, closeTo(108.0, 1e-6));
      expect(sidebarSize.height, 400);
      expect(find.text('toc'), findsOneWidget);
      expect(find.text('reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
