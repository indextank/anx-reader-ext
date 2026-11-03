import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_chrome.dart';
import 'package:anx_reader/widgets/reading_page/reading_panel_coordinator.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

const _ttsFabKey = ValueKey('tts-fab-placeholder');
const _scrimKey = ValueKey('reading-chrome-scrim');
const _themeSubpageKey = ValueKey('theme-subpage');

Future<List<ReadTheme>> _loadThemes() async => const <ReadTheme>[];

Widget _stylePage(
  BuildContext context,
  List<ReadTheme> themes,
  ValueChanged<Widget> setCurrentPage,
) {
  return AppButton(
    label: 'Background',
    onPressed: () => setCurrentPage(
      SingleChildScrollView(
        key: _themeSubpageKey,
        child: Column(
          children: List.generate(
            80,
            (index) => SizedBox(
              height: 24,
              child: Text('theme-subpage-row-$index'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ChromeHarness {
  final chromeKey = GlobalKey<ReadingChromeState>();
  final readerFocusNode = FocusNode(debugLabel: 'chrome-test-reader');
  var tocCalls = 0;
  var showCalls = 0;
  var hideCalls = 0;

  void dispose() => readerFocusNode.dispose();
}

Future<void> _pumpChrome(
  WidgetTester tester,
  _ChromeHarness harness, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await pumpDesignSystem(
    tester,
    Focus(
      focusNode: harness.readerFocusNode,
      child: ReadingChrome(
        key: harness.chromeKey,
        toolbar: ReadingToolbar(
          title: 'Book',
          onBack: () {},
          onToc: () {
            harness.chromeKey.currentState!.hideBottomBar();
            harness.tocCalls++;
          },
          actions: [
            AppIconButton(
              tooltip: 'Notes',
              icon: Icons.edit,
              onPressed: () => harness.chromeKey.currentState!
                  .showToolPanel(ReadingToolPanelKind.notes),
            ),
            AppIconButton(
              tooltip: 'Style',
              icon: Icons.color_lens,
              onPressed: () => harness.chromeKey.currentState!
                  .showToolPanel(ReadingToolPanelKind.style),
            ),
            AppIconButton(
              tooltip: 'Narrator',
              icon: Icons.headphones,
              onPressed: () => harness.chromeKey.currentState!
                  .showToolPanel(ReadingToolPanelKind.tts),
            ),
            AppIconButton(
              tooltip: 'AI',
              icon: Icons.auto_awesome,
              onPressed: () => harness.chromeKey.currentState!.hideBottomBar(),
            ),
          ],
        ),
        onShow: () {
          harness.showCalls++;
          harness.readerFocusNode.unfocus();
        },
        onHide: () {
          harness.hideCalls++;
          harness.readerFocusNode.requestFocus();
        },
        notesBuilder: (_) => const Text('notes-panel'),
        ttsBuilder: (_) => const Text('tts-panel'),
        styleThemesLoader: _loadThemes,
        styleBuilder: _stylePage,
        ttsFab: const SizedBox(key: _ttsFabKey),
      ),
    ),
  );
}

Future<void> _showChrome(WidgetTester tester, _ChromeHarness harness) async {
  harness.chromeKey.currentState!.showBottomBar();
  await tester.pump();
}

Future<void> _openStylePage(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Style'));
  await tester.pump();
  await tester.pump();
}

void _expectClosed(_ChromeHarness harness) {
  expect(find.byType(BottomSheet), findsNothing);
  expect(find.byKey(_ttsFabKey), findsOneWidget);
  expect(harness.readerFocusNode.hasFocus, isTrue);
}

typedef _CoordinatorStyleBuilder = Widget Function(
  BuildContext context,
  List<ReadTheme> themes,
  ValueChanged<Widget> setCurrentPage,
);

class _CoordinatorHarness extends StatefulWidget {
  const _CoordinatorHarness({
    super.key,
    this.styleThemesLoader = _loadThemes,
    this.styleBuilder = _stylePage,
  });

  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final _CoordinatorStyleBuilder styleBuilder;

  @override
  State<_CoordinatorHarness> createState() => _CoordinatorHarnessState();
}

class _CoordinatorHarnessState extends State<_CoordinatorHarness> {
  final coordinatorKey = GlobalKey<ReadingPanelCoordinatorState>();
  final chromeKey = GlobalKey<ReadingChromeState>();
  var aiPosition = AiPanelPositionEnum.right;
  var notesPosition = AiPanelPositionEnum.popup;
  var stylePosition = AiPanelPositionEnum.popup;

  void setNotesPosition(AiPanelPositionEnum value) {
    setState(() => notesPosition = value);
  }

  void setAiPosition(AiPanelPositionEnum value) {
    setState(() => aiPosition = value);
  }

  void setStylePosition(AiPanelPositionEnum value) {
    setState(() => stylePosition = value);
  }

  void _switchPosition(ReadingPanelTool tool) {
    setState(() {
      switch (tool) {
        case ReadingPanelTool.ai:
          aiPosition = aiPosition == AiPanelPositionEnum.right
              ? AiPanelPositionEnum.bottom
              : AiPanelPositionEnum.right;
        case ReadingPanelTool.notes:
          notesPosition = notesPosition == AiPanelPositionEnum.right
              ? AiPanelPositionEnum.popup
              : AiPanelPositionEnum.right;
        case ReadingPanelTool.style:
          stylePosition = stylePosition == AiPanelPositionEnum.right
              ? AiPanelPositionEnum.popup
              : AiPanelPositionEnum.right;
        case ReadingPanelTool.tts:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReadingPanelCoordinator(
      key: coordinatorKey,
      chromeKey: chromeKey,
      reader: const Text('reader-content'),
      toolbar: ReadingToolbar(
        title: 'Book',
        onBack: () {},
        onToc: () {},
        actions: [
          AppIconButton(
            tooltip: 'Notes',
            icon: Icons.edit,
            onPressed: () => coordinatorKey.currentState!
                .showToolPanel(ReadingToolPanelKind.notes),
          ),
          AppIconButton(
            tooltip: 'Style',
            icon: Icons.color_lens,
            onPressed: () => coordinatorKey.currentState!
                .showToolPanel(ReadingToolPanelKind.style),
          ),
          AppIconButton(
            tooltip: 'Narrator',
            icon: Icons.headphones,
            onPressed: () => coordinatorKey.currentState!
                .showToolPanel(ReadingToolPanelKind.tts),
          ),
          AppIconButton(
            tooltip: 'AI',
            icon: Icons.auto_awesome,
            onPressed: () => coordinatorKey.currentState!.showAiPanel(),
          ),
        ],
      ),
      onShow: () {},
      onHide: () {},
      aiBuilder: (_) => const Text('ai-panel'),
      notesBuilder: (_) => const Text('notes-panel'),
      ttsBuilder: (_) => const Text('tts-panel'),
      styleThemesLoader: widget.styleThemesLoader,
      styleBuilder: widget.styleBuilder,
      ttsFab: const SizedBox(key: _ttsFabKey),
      aiPanelPosition: aiPosition,
      notesPanelPosition: notesPosition,
      stylePanelPosition: stylePosition,
      panelWidth: 300,
      panelMinWidth: 240,
      panelMaxWidth: 600,
      aiPanelHeight: 300,
      onPanelResize: (_) {},
      onVerticalPanelResize: (_) {},
      onPanelResizeEnd: () {},
      onSwitchPosition: _switchPosition,
    );
  }
}

Future<_CoordinatorHarnessState> _pumpCoordinator(
  WidgetTester tester, {
  Future<List<ReadTheme>> Function() styleThemesLoader = _loadThemes,
  _CoordinatorStyleBuilder styleBuilder = _stylePage,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harnessKey = GlobalKey<_CoordinatorHarnessState>();
  await pumpDesignSystem(
    tester,
    _CoordinatorHarness(
      key: harnessKey,
      styleThemesLoader: styleThemesLoader,
      styleBuilder: styleBuilder,
    ),
  );
  return harnessKey.currentState!;
}

Future<void> _tapCoordinatorTool(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chrome fills an unpositioned stack slot for bottom-right FAB',
      (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDesignSystem(
      tester,
      Stack(
        children: [
          const SizedBox.expand(),
          ReadingChrome(
            key: harness.chromeKey,
            toolbar: ReadingToolbar(
              title: 'Book',
              onBack: () {},
              onToc: () {},
              actions: const [],
            ),
            onShow: () {},
            onHide: () {},
            notesBuilder: (_) => const SizedBox.shrink(),
            ttsBuilder: (_) => const SizedBox.shrink(),
            styleThemesLoader: _loadThemes,
            styleBuilder: _stylePage,
            ttsFab: const SizedBox(
              key: _ttsFabKey,
              width: 40,
              height: 40,
            ),
          ),
        ],
      ),
    );

    final chromeRect = tester.getRect(find.byType(ReadingChrome));
    final fabRect = tester.getRect(find.byKey(_ttsFabKey));
    expect(chromeRect.size, const Size(1000, 800));
    expect(fabRect.right, greaterThan(900));
    expect(fabRect.bottom, greaterThan(700));
  });

  testWidgets(
      'runtime chrome switches panels repeatedly and closes with focus restored',
      (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    await _pumpChrome(tester, harness, size: const Size(1000, 800));

    final offstage = find.descendant(
      of: find.byType(ReadingChrome),
      matching: find.byType(Offstage),
    );
    expect(tester.widget<Offstage>(offstage).offstage, isTrue);
    expect(find.byKey(_ttsFabKey), findsOneWidget);

    await _showChrome(tester, harness);
    expect(tester.widget<Offstage>(offstage).offstage, isFalse);
    expect(find.byKey(_ttsFabKey), findsNothing);

    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    expect(find.text('notes-panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Narrator'));
    await tester.pump();
    expect(find.text('notes-panel'), findsNothing);
    expect(find.text('tts-panel'), findsOneWidget);

    await _openStylePage(tester);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('tts-panel'), findsNothing);

    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    expect(find.text('notes-panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pump();
    expect(harness.tocCalls, 1);
    _expectClosed(harness);

    await _showChrome(tester, harness);
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    await tester.tap(find.byTooltip('AI'));
    await tester.pump();
    _expectClosed(harness);

    await _showChrome(tester, harness);
    await tester.tap(find.byTooltip('Narrator'));
    await tester.pump();
    await tester.tap(find.byKey(_scrimKey));
    await tester.pump();
    _expectClosed(harness);

    expect(harness.showCalls, 3);
    expect(harness.hideCalls, 3);
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[
    const Size(320, 640),
    const Size(800, 360),
    const Size(800, 1200),
  ]) {
    testWidgets(
        'style subpage enters and returns within chrome at '
        '${size.width}x${size.height}', (tester) async {
      final harness = _ChromeHarness();
      addTearDown(harness.dispose);
      await _pumpChrome(tester, harness, size: size);
      await _showChrome(tester, harness);
      await _openStylePage(tester);

      await tester.tap(find.text('Background'));
      await tester.pump();

      expect(find.byKey(_themeSubpageKey), findsOneWidget);
      final panelRect = tester.getRect(find.byType(BottomSheet));
      expect(
        panelRect.height,
        lessThanOrEqualTo(math.min(size.height * 0.7, 600.0) + 1),
      );
      expect(panelRect.bottom, lessThanOrEqualTo(size.height + 1));
      expect(tester.takeException(), isNull);

      final backTooltip = MaterialLocalizations.of(
        tester.element(find.byType(ReadingToolPanel)),
      ).backButtonTooltip;
      await tester.tap(
        find.descendant(
          of: find.byType(ReadingToolPanel),
          matching: find.byTooltip(backTooltip),
        ),
      );
      await tester.pump();

      expect(find.text('Background'), findsOneWidget);
      expect(find.byKey(_themeSubpageKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closeToolPanel clears only the panel and keeps chrome visible',
      (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    await _pumpChrome(tester, harness, size: const Size(1000, 800));
    await _showChrome(tester, harness);
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);

    harness.chromeKey.currentState!.closeToolPanel();
    await tester.pump();

    final offstage = tester.widget<Offstage>(
      find.descendant(
        of: find.byType(ReadingChrome),
        matching: find.byType(Offstage),
      ),
    );
    expect(offstage.offstage, isFalse);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(_ttsFabKey), findsNothing);
    expect(harness.hideCalls, 0);
  });

  group('unified reading panel coordinator', () {
    testWidgets('notes move from popup to side and AI replaces their content',
        (tester) async {
      final harness = await _pumpCoordinator(tester);
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();

      await _tapCoordinatorTool(tester, 'Notes');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ReadingSidePanelHost), findsNothing);
      expect(find.text('notes-panel'), findsOneWidget);

      harness.setNotesPosition(AiPanelPositionEnum.right);
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReadingSidePanelHost), findsNothing);

      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
      expect(find.text('notes-panel'), findsOneWidget);

      await _tapCoordinatorTool(tester, 'AI');
      expect(
          harness.coordinatorKey.currentState!.activeTool, ReadingPanelTool.ai);
      expect(find.text('ai-panel'), findsOneWidget);
      expect(find.text('notes-panel'), findsNothing);
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
    });

    testWidgets('style moves from popup to side without a sheet shell',
        (tester) async {
      final harness = await _pumpCoordinator(tester);
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();

      await _tapCoordinatorTool(tester, 'Style');
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ReadingSidePanelHost), findsNothing);

      harness.setStylePosition(AiPanelPositionEnum.right);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
      expect(find.text('Background'), findsOneWidget);
    });

    testWidgets('position change clears the previous style subpage',
        (tester) async {
      final harness = await _pumpCoordinator(tester);
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();
      await _tapCoordinatorTool(tester, 'Style');
      await tester.pump();
      await tester.tap(find.text('Background'));
      await tester.pump();
      expect(find.byKey(_themeSubpageKey), findsOneWidget);

      harness.setStylePosition(AiPanelPositionEnum.right);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Background'), findsOneWidget);
      expect(find.byKey(_themeSubpageKey), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
    });

    testWidgets('an old style completer cannot replace the new side session',
        (tester) async {
      final requests = <Completer<List<ReadTheme>>>[];
      final harness = await _pumpCoordinator(
        tester,
        styleThemesLoader: () {
          final request = Completer<List<ReadTheme>>();
          requests.add(request);
          return request.future;
        },
        styleBuilder: (context, themes, setCurrentPage) =>
            Text(themes.isEmpty ? 'style-B' : 'style-A'),
      );
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();
      await _tapCoordinatorTool(tester, 'Style');
      expect(requests, hasLength(1));

      harness.setStylePosition(AiPanelPositionEnum.right);
      await tester.pump();
      await tester.pump();
      expect(requests, hasLength(2));

      requests[1].complete(const <ReadTheme>[]);
      await tester.pump();
      expect(find.text('style-B'), findsOneWidget);

      requests[0].complete(<ReadTheme>[
        ReadTheme(
          backgroundColor: 'FF000000',
          textColor: 'FFFFFFFF',
          backgroundImagePath: '',
        ),
      ]);
      await tester.pump();

      expect(find.text('style-B'), findsOneWidget);
      expect(find.text('style-A'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI split keeps right and bottom presentations compatible',
        (tester) async {
      final harness = await _pumpCoordinator(tester);
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();
      await _tapCoordinatorTool(tester, 'AI');
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
      expect(find.text('ai-panel'), findsOneWidget);

      harness.setAiPosition(AiPanelPositionEnum.bottom);
      await tester.pump();

      expect(find.byType(ReadingSidePanelHost), findsNothing);
      expect(find.text('ai-panel'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('ai-chat-panel'))).height,
          300);

      harness.setAiPosition(AiPanelPositionEnum.right);
      await tester.pump();
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
      expect(find.text('ai-panel'), findsOneWidget);
    });

    testWidgets('tts stays in chrome popup and clears the side host',
        (tester) async {
      final harness = await _pumpCoordinator(tester);
      harness.setNotesPosition(AiPanelPositionEnum.right);
      await tester.pump();
      harness.chromeKey.currentState!.showBottomBar();
      await tester.pump();
      await _tapCoordinatorTool(tester, 'Notes');
      expect(find.byType(ReadingSidePanelHost), findsOneWidget);

      await _tapCoordinatorTool(tester, 'Narrator');

      expect(find.byType(ReadingSidePanelHost), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('tts-panel'), findsOneWidget);
      expect(find.byKey(_ttsFabKey), findsNothing);
    });
  });
}
