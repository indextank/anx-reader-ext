import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/bgimg.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/reading_page.dart' show epubPlayerKey;
import 'package:anx_reader/providers/bgimg.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/reading_page/combined_style_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/notes_widget.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/design_system_test_utils.dart';

const _outerScrollKey = ValueKey('combined-style-settings-scroll');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-combined-style-');
    documentPath = tempDir.path;
    getFontDir().createSync();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('combined page exposes every settings group without tabs or gear',
      (tester) async {
    await _pumpCombined(tester, size: const Size(800, 1200));

    expect(find.byType(TabBar), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('No reading themes yet'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Style'), findsNWidgets(2));
    expect(find.text('Other'), findsOneWidget);
    expect(find.byType(ReadingMoreSettings), findsOneWidget);
    expect(find.byType(StyleSettings), findsOneWidget);
    expect(find.byType(OtherSettings), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StyleWidget),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.byKey(_outerScrollKey), findsOneWidget);

    const expectedItems = [
      'Font Size',
      'Line Spacing',
      'Paragraph Spacing',
      'Page Turning Method',
      'Font',
      'Background',
      'Download Fonts',
      'Writing Direction',
      'Translation Mode',
      'Columncount',
      'Column Threshold',
      'Convert Chinese',
      'Code Highlight Theme',
      'Notes panel position',
      'Style panel position',
      'Reading Info',
      'Header Settings',
      'Footer Settings',
      'Use Book Styles',
      'Indent',
      'Side Margin',
      'Top Margin',
      'Bottom Margin',
      'Letter Spacing',
      'Font Weight',
      'Heading Size',
      'Text Alignment',
      'Enable Custom CSS',
      'Full Screen',
      'Swap Page Turn Area',
      'Mouse Hover to Show Menu',
      'Keyboard Shortcut Turn Page',
      'Auto Adjust Reading Theme',
      'Auto Translate Selection',
      'Auto-mark selection',
      'Auto Summary Previous Content',
      'Screen Timeout',
    ];
    for (final label in expectedItems) {
      expect(find.text(label), findsWidgets,
          reason: '$label must stay visible');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'default StyleWidget keeps its standalone shell and settings gear',
      (tester) async {
    await _pumpWithNavigator(
      tester,
      StyleWidget(
        themes: const [],
        epubPlayerKey: GlobalKey<EpubPlayerState>(),
        setCurrentPage: (_) {},
        hideAppBarAndBottomBar: (_) {},
      ),
    );

    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StyleWidget),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty theme add action creates a theme and opens its editor',
      (tester) async {
    Widget? currentPage;
    await _pumpCombined(
      tester,
      size: const Size(800, 1200),
      themeInserter: (_) async => 7,
      setCurrentPage: (page) => currentPage = page,
    );

    final add = find.descendant(
      of: find.byType(StyleWidget),
      matching: find.byIcon(Icons.add),
    );
    expect(add, findsOneWidget);
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();

    expect(currentPage, isA<ThemeChangeWidget>());
    expect((currentPage! as ThemeChangeWidget).readTheme.id, 7);
    expect(find.text('No reading themes yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls retain prefs writes and player callbacks',
      (tester) async {
    await _pumpCombined(tester, size: const Size(800, 1200));
    final player = epubPlayerKey.currentState! as _TestEpubPlayerState;

    final fontSize = find.byWidgetPredicate(
      (widget) =>
          widget is Slider &&
          widget.min == 0.5 &&
          widget.max == 3 &&
          widget.divisions == 25,
    );
    await tester.ensureVisible(fontSize);
    tester.widget<Slider>(fontSize).onChanged!(1.6);
    await tester.pump();
    expect(Prefs().bookStyle.fontSize, 1.6);
    expect(player.styleChanges.last?.fontSize, 1.6);

    final writingTile = find.ancestor(
      of: find.text('Writing Direction'),
      matching: find.byType(AppListTile),
    );
    final horizontal = find.descendant(
      of: writingTile,
      matching: find.text('Horizontal'),
    );
    await tester.ensureVisible(horizontal);
    await tester.tap(horizontal);
    await tester.pump();
    expect(Prefs().writingMode, WritingModeEnum.horizontalTb);
    expect(Prefs().bookStyle.maxColumnCount, 1);
    expect(player.styleChanges.last?.maxColumnCount, 1);

    await _tapSwitch(tester, 'Use Book Styles');
    expect(Prefs().useBookStyles, isTrue);
    expect(player.styleChanges, isNotEmpty);

    await _tapSwitch(tester, 'Enable Custom CSS');
    expect(Prefs().customCSSEnabled, isTrue);
    final cssField = find.descendant(
      of: find.byType(CustomCSSEditor),
      matching: find.byType(TextField),
    );
    await tester.enterText(cssField, 'p { color: blue; }');
    final saveCss = find.text('Save & Apply');
    await tester.ensureVisible(saveCss);
    await tester.tap(saveCss);
    await tester.pump(const Duration(milliseconds: 100));
    expect(Prefs().customCSS, 'p { color: blue; }');
    expect(find.text('Saved'), findsOneWidget);

    final oldFullScreen = Prefs().hideStatusBar;
    await _tapSwitch(tester, 'Full Screen');
    expect(Prefs().hideStatusBar, !oldFullScreen);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('writing direction then font size preserves other style fields',
      (tester) async {
    await _pumpCombined(tester, size: const Size(800, 1200));
    await _tapWritingDirection(tester, 'Horizontal');
    final before = Prefs().bookStyle;

    await _changeSlider(
      tester,
      _slider(min: 0.5, max: 3, divisions: 25),
      1.7,
    );

    _expectStyleAfter(
      Prefs().bookStyle,
      before,
      fontSize: 1.7,
    );
  });

  testWidgets('writing direction then indent preserves other style fields',
      (tester) async {
    await _pumpCombined(tester, size: const Size(800, 1200));
    await _tapWritingDirection(tester, 'Vertical');
    final before = Prefs().bookStyle;

    await _changeSlider(
      tester,
      _slider(min: -0.5, max: 8, divisions: 17),
      2,
    );

    _expectStyleAfter(
      Prefs().bookStyle,
      before,
      indent: 2,
    );
  });

  testWidgets('default and advanced sliders preserve edits in both directions',
      (tester) async {
    await _pumpCombined(tester, size: const Size(800, 1200));
    await _changeSlider(
      tester,
      _slider(min: 0.5, max: 3, divisions: 25),
      1.8,
    );
    final afterFontSize = Prefs().bookStyle;
    await _changeSlider(
      tester,
      _slider(min: 100, max: 900, divisions: 8),
      500,
    );
    _expectStyleAfter(
      Prefs().bookStyle,
      afterFontSize,
      fontWeight: 500,
    );

    final afterFontWeight = Prefs().bookStyle;
    await _changeSlider(
      tester,
      _slider(min: 0.5, max: 3, divisions: 25),
      1.5,
    );
    _expectStyleAfter(
      Prefs().bookStyle,
      afterFontWeight,
      fontSize: 1.5,
    );
  });

  testWidgets('theme load failure retries to the combined empty state',
      (tester) async {
    var attempts = 0;
    await _pumpWithNavigator(
      tester,
      ReadingToolPanel(
        kind: ReadingToolPanelKind.style,
        notesBuilder: (_) => const SizedBox.shrink(),
        ttsBuilder: (_) => const SizedBox.shrink(),
        styleThemesLoader: () async {
          attempts++;
          if (attempts == 1) throw StateError('private theme failure');
          return const <ReadTheme>[];
        },
        styleBuilder: (context, themes, setCurrentPage) =>
            CombinedStyleSettings(
          themes: themes,
          epubPlayerKey: GlobalKey<EpubPlayerState>(),
          setCurrentPage: setCurrentPage,
          hideAppBarAndBottomBar: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private theme failure'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.byType(CombinedStyleSettings), findsOneWidget);
    expect(find.text('No reading themes yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real background page enters and returns from combined page',
      (tester) async {
    final container = ProviderContainer(
      overrides: [bgimgProvider.overrideWith(_EmptyBgimg.new)],
    );
    addTearDown(container.dispose);
    await _pumpWithNavigator(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: Column(
          children: [
            const Spacer(),
            ReadingToolPanel(
              kind: ReadingToolPanelKind.style,
              notesBuilder: (_) => const SizedBox.shrink(),
              ttsBuilder: (_) => const SizedBox.shrink(),
              styleThemesLoader: () async => const <ReadTheme>[],
              styleBuilder: (context, themes, setCurrentPage) =>
                  CombinedStyleSettings(
                themes: themes,
                epubPlayerKey: GlobalKey<EpubPlayerState>(),
                setCurrentPage: setCurrentPage,
                hideAppBarAndBottomBar: (_) {},
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.ensureVisible(find.text('Background'));
    await tester.tap(find.text('Background'));
    await tester.pump();
    expect(find.byType(BgimgSelector), findsOneWidget);
    expect(find.byType(CombinedStyleSettings), findsNothing);
    expect(tester.takeException(), isNull);

    final backTooltip = MaterialLocalizations.of(
      tester.element(find.byType(ReadingToolPanel)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pump();
    expect(find.byType(BgimgSelector), findsNothing);
    expect(find.byType(CombinedStyleSettings), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading notes shows a real provider loading then empty state',
      (tester) async {
    final book = Book.mock();
    final pending = Completer<BookNotesState>();
    await _pumpNotes(
      tester,
      book,
      _PendingBookNotes(pending),
      size: const Size(360, 640),
    );

    expect(find.byType(AppLoadingIndicator), findsOneWidget);
    expect(find.byType(BookNotesList), findsOneWidget);
    pending.complete(_emptyNotesState(book));
    await _pumpAsyncFrames(tester);

    expect(find.byType(AppLoadingIndicator), findsNothing);
    expect(find.byType(NotesTips), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading notes provider error retries without leaking details',
      (tester) async {
    final book = Book.mock();
    final notes = _FlakyBookNotes(book);
    await _pumpNotes(tester, book, notes, size: const Size(360, 640));
    await _pumpAsyncFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private notes failure'), findsNothing);
    notes.shouldFail = false;
    await tester.tap(find.text('Retry'));
    await _pumpAsyncFrames(tester);

    expect(find.byType(AppErrorState), findsNothing);
    expect(find.byType(NotesTips), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final sideContent in [false, true]) {
    for (final size in <Size>[
      const Size(320, 640),
      const Size(800, 360),
      const Size(800, 1200),
    ]) {
      testWidgets(
          'combined ${sideContent ? 'side' : 'popup'} panel scrolls without '
          'overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var closes = 0;
        final panel = ReadingToolPanel(
          kind: ReadingToolPanelKind.style,
          notesBuilder: (_) => const SizedBox.shrink(),
          ttsBuilder: (_) => const SizedBox.shrink(),
          styleThemesLoader: () async => const <ReadTheme>[],
          styleBuilder: (context, themes, setCurrentPage) =>
              CombinedStyleSettings(
            themes: themes,
            epubPlayerKey: epubPlayerKey,
            setCurrentPage: setCurrentPage,
            hideAppBarAndBottomBar: (_) {},
          ),
          sideContent: sideContent,
        );
        final content = sideContent
            ? Row(
                children: [
                  Offstage(child: _TestEpubPlayer(key: epubPlayerKey)),
                  const Expanded(child: SizedBox.shrink()),
                  ReadingSidePanelHost(
                    width: math.min(360, size.width),
                    minWidth: 0,
                    maxWidth: size.width,
                    onResize: (_) {},
                    onResizeEnd: () {},
                    onSwitchPosition: () {},
                    onClose: () => closes++,
                    child: panel,
                  ),
                ],
              )
            : Column(
                children: [
                  Offstage(child: _TestEpubPlayer(key: epubPlayerKey)),
                  const Spacer(),
                  panel,
                ],
              );
        await _pumpWithNavigator(tester, content);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(readingToolPanelSurfaceKey),
          sideContent ? findsNothing : findsOneWidget,
        );
        final outerScrollable = find
            .descendant(
              of: find.byKey(_outerScrollKey),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(tester.takeException(), isNull);
        final position =
            tester.state<ScrollableState>(outerScrollable).position;
        expect(tester.takeException(), isNull);
        expect(position.maxScrollExtent, greaterThan(0));
        await tester.dragUntilVisible(
          find.text('Screen Timeout'),
          outerScrollable,
          const Offset(0, -200),
          maxIteration: 100,
        );
        await tester.pump();
        expect(find.text('Screen Timeout'), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (sideContent) {
          await tester.tap(find.byTooltip('Close'));
          await tester.pump();
          expect(closes, 1);
        }
      });
    }
  }

  testWidgets('240px host keeps scrolling close and theme retry accessible',
      (tester) async {
    tester.view.physicalSize = const Size(800, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;
    var closes = 0;
    await _pumpWithNavigator(
      tester,
      Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          ReadingSidePanelHost(
            width: 240,
            minWidth: 0,
            maxWidth: 600,
            onResize: (_) {},
            onResizeEnd: () {},
            onSwitchPosition: () {},
            onClose: () => closes++,
            child: ReadingToolPanel(
              kind: ReadingToolPanelKind.style,
              notesBuilder: (_) => const SizedBox.shrink(),
              ttsBuilder: (_) => const SizedBox.shrink(),
              styleThemesLoader: () async {
                attempts++;
                if (attempts == 1) throw StateError('private theme failure');
                return const <ReadTheme>[];
              },
              styleBuilder: (context, themes, setCurrentPage) =>
                  CombinedStyleSettings(
                themes: themes,
                epubPlayerKey: epubPlayerKey,
                setCurrentPage: setCurrentPage,
                hideAppBarAndBottomBar: (_) {},
              ),
              sideContent: true,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(ReadingSidePanelHost)).width, 240);
    expect(find.byType(AppErrorState), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CombinedStyleSettings), findsOneWidget);
    expect(tester.takeException(), isNull);

    final outerScrollable = find
        .descendant(
          of: find.byKey(_outerScrollKey),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.dragUntilVisible(
      find.text('Screen Timeout'),
      outerScrollable,
      const Offset(0, -200),
      maxIteration: 100,
    );
    expect(find.text('Screen Timeout'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side notes fill their parent and retain an internal scroll list',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final book = Book.mock();
    await _pumpWithNavigator(
      tester,
      ProviderScope(
        overrides: [
          bookNotesControllerProvider(book).overrideWith(
            () => _EmptyBookNotes(book),
          ),
        ],
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 700,
            child: ReadingNotes(book: book),
          ),
        ),
      ),
    );
    await _pumpAsyncFrames(tester);

    expect(tester.getSize(find.byType(ReadingNotes)).height, 700);
    final notesRect = tester.getRect(find.byType(ReadingNotes));
    final list = find.descendant(
      of: find.byType(ReadingNotes),
      matching: find.byType(ListView),
    );
    expect(list, findsOneWidget);
    expect(
        tester.getRect(list).bottom, lessThanOrEqualTo(notesRect.bottom + 1));
    expect(tester.getSize(list).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('popup notes use the bounded panel height without overflow',
      (tester) async {
    for (final size in <Size>[
      const Size(320, 640),
      const Size(800, 360),
      const Size(800, 1200),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final book = Book.mock();
      await _pumpWithNavigator(
        tester,
        ProviderScope(
          overrides: [
            bookNotesControllerProvider(book).overrideWith(
              () => _EmptyBookNotes(book),
            ),
          ],
          child: Column(
            children: [
              const Spacer(),
              ReadingToolPanel(
                kind: ReadingToolPanelKind.notes,
                notesBuilder: (_) => ReadingNotes(book: book),
                ttsBuilder: (_) => const SizedBox.shrink(),
                styleThemesLoader: () async => const <ReadTheme>[],
                styleBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      await _pumpAsyncFrames(tester);

      expect(find.byKey(readingToolPanelSurfaceKey), findsOneWidget);
      expect(tester.getSize(find.byType(ReadingNotes)).height, greaterThan(0));
      expect(tester.takeException(), isNull,
          reason: 'notes overflow at ${size.width}x${size.height}');
    }
    addTearDown(tester.view.reset);
  });
}

Future<void> _pumpWithNavigator(WidgetTester tester, Widget child) async {
  await pumpDesignSystem(
    tester,
    Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    ),
  );
}

Future<void> _pumpCombined(
  WidgetTester tester, {
  required Size size,
  Future<int> Function(ReadTheme)? themeInserter,
  ValueChanged<Widget>? setCurrentPage,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _pumpWithNavigator(
    tester,
    Column(
      children: [
        Offstage(child: _TestEpubPlayer(key: epubPlayerKey)),
        Expanded(
          child: CombinedStyleSettings(
            themes: const [],
            epubPlayerKey: epubPlayerKey,
            setCurrentPage: setCurrentPage ?? (_) {},
            hideAppBarAndBottomBar: (_) {},
            themeInserter: themeInserter,
          ),
        ),
      ],
    ),
  );
}

Finder _slider({
  required double min,
  required double max,
  required int divisions,
}) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Slider &&
        widget.min == min &&
        widget.max == max &&
        widget.divisions == divisions,
  );
}

Future<void> _changeSlider(
  WidgetTester tester,
  Finder slider,
  double value,
) async {
  expect(slider, findsOneWidget);
  await tester.ensureVisible(slider);
  tester.widget<Slider>(slider).onChanged!(value);
  await tester.pump();
  expect(tester.widget<Slider>(slider).value, value);
}

Future<void> _tapWritingDirection(WidgetTester tester, String label) async {
  final writingTile = find.ancestor(
    of: find.text('Writing Direction'),
    matching: find.byType(AppListTile),
  );
  final option = find.descendant(
    of: writingTile,
    matching: find.text(label),
  );
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
}

void _expectStyleAfter(
  BookStyle actual,
  BookStyle before, {
  double? fontSize,
  double? lineHeight,
  double? fontWeight,
  double? indent,
}) {
  final expected = before.copyWith(
    fontSize: fontSize,
    lineHeight: lineHeight,
    fontWeight: fontWeight,
    indent: indent,
  );
  expect(actual.toMap(), expected.toMap());
}

Future<void> _tapSwitch(WidgetTester tester, String title) async {
  final tile = find.ancestor(
    of: find.text(title),
    matching: find.byType(AppListTile),
  );
  final toggle = find.descendant(
    of: tile,
    matching: find.byType(Switch),
  );
  expect(toggle, findsOneWidget, reason: title);
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pump();
}

Future<void> _pumpNotes(
  WidgetTester tester,
  Book book,
  BookNotesController notes, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _pumpWithNavigator(
    tester,
    ProviderScope(
      overrides: [
        bookNotesControllerProvider(book).overrideWith(() => notes),
      ],
      child: SizedBox(
        width: size.width,
        height: 400,
        child: ReadingNotes(book: book),
      ),
    ),
  );
}

Future<void> _pumpAsyncFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

BookNotesState _emptyNotesState(Book book) => BookNotesState(
      book: book,
      allNotes: const [],
      visibleNotes: const [],
      viewSortMode: const NotesSortMode(
        field: NotesSortField.createdTime,
        direction: SortDirection.desc,
      ),
      exportSortMode: const NotesSortMode(
        field: NotesSortField.createdTime,
        direction: SortDirection.desc,
      ),
      showBookmarks: true,
      enabledTypeColors: const {},
      selectedNoteIds: const {},
    );

class _TestEpubPlayer extends EpubPlayer {
  _TestEpubPlayer({super.key})
      : super(
          book: _playerBook,
          showOrHideAppBarAndBottomBar: _ignore,
          onLoadEnd: _ignore,
          initialThemes: const [],
          updateParent: _ignore,
        );

  @override
  ConsumerState<EpubPlayer> createState() => _TestEpubPlayerState();
}

final _playerBook = Book.mock();

void _ignore([Object? _]) {}

class _TestEpubPlayerState extends EpubPlayerState {
  final styleChanges = <BookStyle?>[];

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void changeStyle(BookStyle? bookStyle) {
    styleChanges.add(bookStyle?.copyWith());
  }
}

class _PendingBookNotes extends BookNotesController {
  _PendingBookNotes(this.pending);

  final Completer<BookNotesState> pending;

  @override
  Future<BookNotesState> build(Book book) => pending.future;
}

class _FlakyBookNotes extends BookNotesController {
  _FlakyBookNotes(this.testBook);

  final Book testBook;
  var shouldFail = true;

  @override
  Future<BookNotesState> build(Book book) async {
    if (shouldFail) throw StateError('private notes failure');
    return _emptyNotesState(testBook);
  }
}

class _EmptyBookNotes extends BookNotesController {
  _EmptyBookNotes(this.testBook);

  final Book testBook;

  @override
  Future<BookNotesState> build(Book book) async => _emptyNotesState(testBook);
}

class _EmptyBgimg extends Bgimg {
  @override
  List<BgimgModel> build() => const [
        BgimgModel(
          type: BgimgType.none,
          path: 'none',
          alignment: BgimgAlignment.center,
        ),
      ];
}
