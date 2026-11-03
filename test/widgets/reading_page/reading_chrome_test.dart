import 'dart:math' as math;

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/reading_chrome.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
