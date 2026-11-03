import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

Widget _unusedBuilder(BuildContext context) => const SizedBox.shrink();

Future<List<ReadTheme>> _unusedThemesLoader() =>
    Future<List<ReadTheme>>.value(const <ReadTheme>[]);

Widget _unusedStyleBuilder(
  BuildContext context,
  List<ReadTheme> themes,
  ValueChanged<Widget> setCurrentPage,
) =>
    const SizedBox.shrink();

Widget _host({
  required ValueNotifier<ReadingToolPanelKind> kind,
  WidgetBuilder notesBuilder = _unusedBuilder,
  WidgetBuilder ttsBuilder = _unusedBuilder,
  Future<List<ReadTheme>> Function() styleThemesLoader = _unusedThemesLoader,
  Widget Function(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) styleBuilder = _unusedStyleBuilder,
}) {
  return ValueListenableBuilder<ReadingToolPanelKind>(
    valueListenable: kind,
    builder: (context, currentKind, child) => ReadingToolPanel(
      kind: currentKind,
      notesBuilder: notesBuilder,
      ttsBuilder: ttsBuilder,
      styleThemesLoader: styleThemesLoader,
      styleBuilder: styleBuilder,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('none does not create a bottom sheet or panel', (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.none);
    addTearDown(kind.dispose);

    await pumpDesignSystem(tester, _host(kind: kind));

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('reading-tool-panel')), findsNothing);
  });

  testWidgets('host replaces notes with tts and clears on none',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.notes);
    addTearDown(kind.dispose);

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        notesBuilder: (context) => const Text('notes-panel'),
        ttsBuilder: (context) => const Text('tts-panel'),
      ),
    );

    expect(find.text('notes-panel'), findsOneWidget);
    expect(find.text('tts-panel'), findsNothing);

    kind.value = ReadingToolPanelKind.tts;
    await tester.pump();

    expect(find.text('notes-panel'), findsNothing);
    expect(find.text('tts-panel'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);

    kind.value = ReadingToolPanelKind.none;
    await tester.pump();

    expect(find.text('tts-panel'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('style retries loading and replaces its internal page',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    var attempts = 0;

    Future<List<ReadTheme>> loadThemes() async {
      attempts++;
      if (attempts == 1) {
        throw StateError('private database detail');
      }
      return const <ReadTheme>[];
    }

    Widget styleBuilder(
      BuildContext context,
      List<ReadTheme> themes,
      ValueChanged<Widget> setCurrentPage,
    ) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('style-panel'),
          AppButton(
            label: 'Background',
            onPressed: () => setCurrentPage(const Text('background-panel')),
          ),
        ],
      );
    }

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        styleThemesLoader: loadThemes,
        styleBuilder: styleBuilder,
      ),
    );

    await tester.pump();

    expect(
      find.text("Content couldn't be loaded. Try again."),
      findsOneWidget,
    );
    expect(find.textContaining('private database detail'), findsNothing);

    await tester.tap(find.text('Retry'));
    for (var i = 0;
        i < 10 && find.text('style-panel').evaluate().isEmpty;
        i++) {
      await tester.pump();
    }

    expect(attempts, 2);
    expect(find.text('style-panel'), findsOneWidget);

    await tester.tap(find.text('Background'));
    await tester.pump();

    expect(find.text('background-panel'), findsOneWidget);
    expect(find.text('style-panel'), findsNothing);
  });

  testWidgets('stale style future does not replace the notes panel',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    final themes = Completer<List<ReadTheme>>();

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        notesBuilder: (context) => const Text('notes-panel'),
        styleThemesLoader: () => themes.future,
        styleBuilder: (context, themes, setCurrentPage) =>
            const Text('style-panel'),
      ),
    );

    kind.value = ReadingToolPanelKind.notes;
    await tester.pump();

    themes.complete(const <ReadTheme>[]);
    await tester.pump();

    expect(find.text('notes-panel'), findsOneWidget);
    expect(find.text('style-panel'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
