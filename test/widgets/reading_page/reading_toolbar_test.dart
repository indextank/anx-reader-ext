import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const longBookTitle =
      'An exceptionally long book title that must stay on one line and '
      'ellipsize when horizontal space is limited';

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
      title: longBookTitle,
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
      orderedEquals([
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
    final semanticsHandle = tester.ensureSemantics();
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

    final backButtonFinder = find.ancestor(
      of: find.byIcon(Icons.arrow_back),
      matching: find.byType(AppIconButton),
    );
    final backTooltip = MaterialLocalizations.of(
      tester.element(find.byType(ReadingToolbar)),
    ).backButtonTooltip;
    expect(find.byTooltip(backTooltip), findsOneWidget);
    expect(find.bySemanticsLabel(backTooltip), findsWidgets);
    expect(
      tester.widget<AppIconButton>(backButtonFinder).semanticLabel,
      backTooltip,
    );

    await tester.tap(backButtonFinder);

    expect(backCalls, 1);
    semanticsHandle.dispose();
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
      orderedEquals([
        Icons.toc,
        Icons.arrow_back,
        EvaIcons.edit,
        Icons.color_lens,
        EvaIcons.headphones,
        Icons.copy,
        Icons.bookmark_border,
        EvaIcons.more_vertical,
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

    final titleFinder = find.text(longBookTitle);
    final titleText = tester.widget<Text>(titleFinder);
    expect(titleText.maxLines, 1);
    expect(titleText.overflow, TextOverflow.ellipsis);
    final theme = Theme.of(tester.element(find.byType(ReadingToolbar)));
    expect(
      titleText.style,
      theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
    );
    expect(
      find.ancestor(
        of: titleFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.header == true,
        ),
      ),
      findsOneWidget,
    );

    final scrollFinder = find.byKey(
      const ValueKey('reading-toolbar-actions-scroll'),
    );
    expect(scrollFinder, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(scrollFinder).scrollDirection,
      Axis.horizontal,
    );

    final scrollableFinder = find.descendant(
      of: scrollFinder,
      matching: find.byType(Scrollable),
    );
    final initialOffset =
        tester.state<ScrollableState>(scrollableFinder).position.pixels;

    await tester.drag(scrollFinder, const Offset(-240, 0));
    await tester.pumpAndSettle();

    final scrolledOffset =
        tester.state<ScrollableState>(scrollableFinder).position.pixels;
    expect(scrolledOffset, greaterThan(initialOffset));
    expect(scrolledOffset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow toolbar respects top view padding and app bar surface',
      (tester) async {
    const topPadding = 32.0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(top: topPadding);
    addTearDown(tester.view.reset);

    await pumpDesignSystem(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: topPadding),
          viewPadding: EdgeInsets.only(top: topPadding),
        ),
        child: toolbar(
          onToc: () {},
          onNotes: () {},
          onStyle: () {},
          onTts: () {},
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    final toolbarFinder = find.byType(ReadingToolbar);
    final toolbarContext = tester.element(toolbarFinder);
    final mediaQuery = MediaQuery.of(toolbarContext);
    expect(mediaQuery.viewPadding.top, topPadding);
    expect(mediaQuery.padding.top, topPadding);
    expect(mediaQuery.viewInsets.top, 0);

    final tocButton = find.ancestor(
      of: find.byIcon(Icons.toc),
      matching: find.byType(AppIconButton),
    );
    final backButton = find.ancestor(
      of: find.byIcon(Icons.arrow_back),
      matching: find.byType(AppIconButton),
    );
    expect(tester.getTopLeft(tocButton).dy, greaterThanOrEqualTo(topPadding));
    expect(tester.getTopLeft(backButton).dy, greaterThanOrEqualTo(topPadding));

    final safeAreaFinder = find.descendant(
      of: toolbarFinder,
      matching: find.byType(AppSafeArea),
    );
    expect(safeAreaFinder, findsOneWidget);
    expect(tester.widget<AppSafeArea>(safeAreaFinder).bottom, isFalse);

    final materialFinder = find.descendant(
      of: toolbarFinder,
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.canvas,
      ),
    );
    expect(materialFinder, findsOneWidget);
    final theme = Theme.of(toolbarContext);
    expect(
      tester.widget<Material>(materialFinder).color,
      theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
    );
    expect(tester.takeException(), isNull);
  });
}
