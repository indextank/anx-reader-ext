import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/bookmark.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_player/image_viewer.dart';
import 'package:anx_reader/widgets/context_menu/context_menu.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bookmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('invalid image data exposes an understandable error state',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const ImageViewer(image: 'not-base64', bookName: 'Book'),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmark item remains usable at 1.3 text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpDesignSystem(
      tester,
      BookmarkItem(
        bookmark: BookmarkModel(
          id: 1,
          bookId: 1,
          content: 'A long bookmark excerpt that wraps onto multiple lines',
          cfi: 'cfi',
          chapter: 'A chapter title that should remain readable',
          percentage: 0.25,
          updateTime: DateTime(2024),
        ),
        onTap: (_) {},
        onDelete: (_) async {},
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('nested TOC item remains usable at 1.3 text scale',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpDesignSystem(
      tester,
      TocItemWidget(
        tocItem: TocItem(
          id: '1',
          href: 'chapter.xhtml',
          label: 'A long nested chapter title that wraps instead of clipping',
          subitems: const [],
          level: 2,
          startPage: 1,
          startPercentage: 0.25,
        ),
        depth: 2,
        isExpanded: false,
        isSelected: true,
        showProgress: true,
        progressText: '12 / 34',
        onToggle: null,
        onTap: () {},
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('25.00%'), findsOneWidget);
  });

  test('context menu safe viewport preserves the original WebView rect', () {
    const webViewRect = Rect.fromLTWH(0, 0, 400, 800);
    final safeRect = readingMenuSafeViewport(
      webViewRect,
      const EdgeInsets.only(left: 8, top: 24, right: 12, bottom: 20),
    );

    expect(safeRect, const Rect.fromLTRB(8, 24, 388, 780));
    expect(webViewRect, const Rect.fromLTWH(0, 0, 400, 800));
  });

  test('context menu recomputes geometry after size and orientation change',
      () {
    const normalizedSelection = Rect.fromLTRB(0.1, 0.2, 0.5, 0.25);
    final portrait = ReadingMenuGeometry.resolve(
      viewportRect: const Rect.fromLTWH(0, 0, 400, 800),
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      viewInsets: EdgeInsets.zero,
      normalizedSelection: normalizedSelection,
      footnote: false,
    );
    final landscape = ReadingMenuGeometry.resolve(
      viewportRect: const Rect.fromLTWH(0, 0, 800, 400),
      padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
      viewInsets: EdgeInsets.zero,
      normalizedSelection: normalizedSelection,
      footnote: false,
    );

    expect(portrait.safeViewportRect, const Rect.fromLTRB(0, 24, 400, 780));
    expect(
      portrait.selectionRect,
      const Rect.fromLTRB(40, 160, 200, 200),
    );
    expect(portrait.menuConstraints.maxHeight, 550);

    expect(landscape.safeViewportRect, const Rect.fromLTRB(24, 24, 780, 380));
    expect(
      landscape.selectionRect,
      const Rect.fromLTRB(80, 80, 400, 100),
    );
    expect(landscape.menuConstraints.maxHeight, 324);

    final portraitPlacement = resolveReadingMenuPlacement(
      axis: Axis.horizontal,
      geometry: portrait,
      menuSize: const Size(300, 200),
      horizontalMargin: 16,
      verticalMargin: 16,
      gap: 12,
    );
    final landscapePlacement = resolveReadingMenuPlacement(
      axis: Axis.horizontal,
      geometry: landscape,
      menuSize: const Size(300, 200),
      horizontalMargin: 16,
      verticalMargin: 16,
      gap: 12,
    );

    expect(portraitPlacement.offset, isNot(landscapePlacement.offset));
    expect(
      landscapePlacement.offset.dy,
      inInclusiveRange(16, 184),
    );
  });

  testWidgets('open context menu updates position after metrics change',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const normalizedSelection = Rect.fromLTRB(0.1, 0.2, 0.5, 0.25);
    final portrait = ReadingMenuGeometry.resolve(
      viewportRect: const Rect.fromLTWH(0, 0, 400, 800),
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      viewInsets: EdgeInsets.zero,
      normalizedSelection: normalizedSelection,
      footnote: true,
    );
    final landscape = ReadingMenuGeometry.resolve(
      viewportRect: const Rect.fromLTWH(0, 0, 800, 400),
      padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
      viewInsets: EdgeInsets.zero,
      normalizedSelection: normalizedSelection,
      footnote: true,
    );
    var geometry = portrait;

    await pumpDesignSystem(
      tester,
      Stack(
        children: [
          ReadingContextMenuOverlay(
            axis: Axis.horizontal,
            initialGeometry: portrait,
            geometryResolver: (_) => geometry,
            annoContent: 'selection',
            annoCfi: 'cfi',
            annoId: null,
            footnote: true,
            decoration: const BoxDecoration(),
            onClose: () {},
            initialPlacement: resolveReadingMenuPlacement(
              axis: Axis.horizontal,
              geometry: portrait,
              menuSize: const Size(200, 100),
              horizontalMargin: 16,
              verticalMargin: 16,
              gap: 12,
            ),
            showTranslationDefault: false,
            horizontalMargin: 16,
            verticalMargin: 16,
            gap: 12,
            menuBuilder: (_) => const SizedBox(
              key: ValueKey('menu-probe'),
              width: 200,
              height: 100,
            ),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final initial = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('menu-probe')),
            matching: find.byType(Positioned),
          )
          .first,
    );

    geometry = landscape;
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    tester.binding.handleMetricsChanged();
    await tester.pump(const Duration(milliseconds: 50));

    final updated = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('menu-probe')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(
      Offset(updated.left!, updated.top!),
      isNot(Offset(initial.left!, initial.top!)),
    );
    expect(updated.left, greaterThanOrEqualTo(24));
    expect(updated.top, greaterThanOrEqualTo(24));
  });
}
