import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 800);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  ReadingToolbar toolbar({
    required VoidCallback onToc,
    required VoidCallback onNotes,
    required VoidCallback onStyle,
    required VoidCallback onTts,
    bool showAi = true,
  }) {
    return ReadingToolbar(
      title: 'A book title that stays on one line',
      onBack: () {},
      onToc: onToc,
      actions: [
        AppIconButton(
          icon: EvaIcons.edit,
          tooltip: 'Notes',
          onPressed: onNotes,
        ),
        AppIconButton(
          icon: Icons.color_lens,
          tooltip: 'Style',
          onPressed: onStyle,
        ),
        AppIconButton(
          icon: EvaIcons.headphones,
          tooltip: 'Narrator',
          onPressed: onTts,
        ),
        if (showAi)
          AppIconButton(
            icon: Icons.auto_awesome,
            tooltip: 'Chat',
            onPressed: () {},
          ),
        AppIconButton(
          icon: Icons.copy,
          tooltip: 'Copy chapter content',
          onPressed: () {},
        ),
        AppIconButton(
          icon: Icons.bookmark_border,
          tooltip: 'Bookmark this page',
          onPressed: () {},
        ),
        AppIconButton(
          icon: EvaIcons.more_vertical,
          tooltip: 'Book details',
          onPressed: () {},
        ),
      ],
    );
  }

  testWidgets('wide toolbar preserves action order and invokes callbacks',
      (tester) async {
    var tocCalls = 0;
    var notesCalls = 0;
    var styleCalls = 0;
    var ttsCalls = 0;

    await pumpDesignSystem(
      tester,
      toolbar(
        onToc: () => tocCalls++,
        onNotes: () => notesCalls++,
        onStyle: () => styleCalls++,
        onTts: () => ttsCalls++,
      ),
    );

    final toolbarFinder = find.byType(ReadingToolbar);
    final icons = tester
        .widgetList<Icon>(
          find.descendant(of: toolbarFinder, matching: find.byType(Icon)),
        )
        .map((icon) => icon.icon)
        .toList();

    expect(
      icons,
      containsAllInOrder([
        Icons.toc,
        Icons.arrow_back,
        EvaIcons.edit,
        Icons.color_lens,
        EvaIcons.headphones,
        Icons.auto_awesome,
        Icons.copy,
        Icons.bookmark_border,
        EvaIcons.more_vertical,
      ]),
    );
    expect(icons, isNot(contains(Icons.data_usage)));
    expect(
      find.descendant(of: toolbarFinder, matching: find.byType(BottomSheet)),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Contents'));
    await tester.tap(find.byTooltip('Notes'));
    await tester.tap(find.byTooltip('Style'));
    await tester.tap(find.byTooltip('Narrator'));

    expect(tocCalls, 1);
    expect(notesCalls, 1);
    expect(styleCalls, 1);
    expect(ttsCalls, 1);
  });

  testWidgets('back button invokes its callback exactly once', (tester) async {
    var backCalls = 0;

    await pumpDesignSystem(
      tester,
      ReadingToolbar(
        title: 'Book',
        onBack: () => backCalls++,
        onToc: () {},
        actions: const [],
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(ReadingToolbar),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );

    expect(backCalls, 1);
  });

  testWidgets('hidden AI action does not change remaining action order',
      (tester) async {
    await pumpDesignSystem(
      tester,
      toolbar(
        onToc: () {},
        onNotes: () {},
        onStyle: () {},
        onTts: () {},
        showAi: false,
      ),
    );

    final icons = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(ReadingToolbar),
            matching: find.byType(Icon),
          ),
        )
        .map((icon) => icon.icon)
        .toList();

    expect(icons, isNot(contains(Icons.auto_awesome)));
    expect(
      icons,
      containsAllInOrder([
        EvaIcons.edit,
        Icons.color_lens,
        EvaIcons.headphones,
        Icons.copy,
      ]),
    );
  });

  testWidgets('narrow toolbar scrolls actions without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDesignSystem(
      tester,
      toolbar(
        onToc: () {},
        onNotes: () {},
        onStyle: () {},
        onTts: () {},
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    final scrollFinder = find.byKey(
      const ValueKey('reading-toolbar-actions-scroll'),
    );
    expect(scrollFinder, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(scrollFinder).scrollDirection,
      Axis.horizontal,
    );

    await tester.drag(scrollFinder, const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
