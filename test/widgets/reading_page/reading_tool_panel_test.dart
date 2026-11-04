import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/models/bgimg.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/providers/bgimg.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool sideContent = false,
}) {
  return ValueListenableBuilder<ReadingToolPanelKind>(
    valueListenable: kind,
    builder: (context, currentKind, child) => ReadingToolPanel(
      kind: currentKind,
      notesBuilder: notesBuilder,
      ttsBuilder: ttsBuilder,
      styleThemesLoader: styleThemesLoader,
      styleBuilder: styleBuilder,
      sideContent: sideContent,
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

  testWidgets('side content reuses style loading without a bottom sheet shell',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);

    await pumpDesignSystem(
      tester,
      SizedBox(
        width: 300,
        height: 800,
        child: _host(
          kind: kind,
          sideContent: true,
          styleBuilder: (context, themes, setCurrentPage) =>
              const Text('side-style-panel'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('side-style-panel'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('reading-tool-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side notes content has no bottom sheet shell', (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.notes);
    addTearDown(kind.dispose);

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        sideContent: true,
        notesBuilder: (_) => const Text('side-notes-panel'),
      ),
    );

    expect(find.text('side-notes-panel'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('side style retries and enters a secondary page without a sheet',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    var attempts = 0;

    await pumpDesignSystem(
      tester,
      SizedBox(
        width: 300,
        height: 800,
        child: _host(
          kind: kind,
          sideContent: true,
          styleThemesLoader: () async {
            attempts++;
            if (attempts == 1) throw StateError('private theme failure');
            return const <ReadTheme>[];
          },
          styleBuilder: (context, themes, setCurrentPage) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(themes.isEmpty ? 'side-empty-themes' : 'side-themes'),
              AppButton(
                label: 'Background',
                onPressed: () => setCurrentPage(const Text('side-background')),
              ),
            ],
          ),
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
    expect(find.text('side-empty-themes'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Background'));
    await tester.pump();
    expect(find.text('side-background'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    final backTooltip = MaterialLocalizations.of(
      tester.element(find.byType(ReadingToolPanel)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pump();
    expect(find.text('side-empty-themes'), findsOneWidget);
    expect(find.text('side-background'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side style ignores stale requests after changing presentation',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    final requestA = Completer<List<ReadTheme>>();
    final requestB = Completer<List<ReadTheme>>();
    final requests = <Completer<List<ReadTheme>>>[requestA, requestB];
    var attempts = 0;

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        sideContent: true,
        styleThemesLoader: () => requests[attempts++].future,
        styleBuilder: (context, themes, setCurrentPage) =>
            Text(themes.isEmpty ? 'side-B' : 'side-A'),
      ),
    );
    await tester.pump();

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        styleThemesLoader: () => requests[attempts++].future,
        styleBuilder: (context, themes, setCurrentPage) =>
            Text(themes.isEmpty ? 'popup-B' : 'popup-A'),
      ),
    );
    await tester.pump();
    requestB.complete(const <ReadTheme>[]);
    await tester.pump();
    expect(find.text('popup-B'), findsOneWidget);

    requestA.complete(<ReadTheme>[
      ReadTheme(
        backgroundColor: 'FF000000',
        textColor: 'FFFFFFFF',
        backgroundImagePath: '',
      ),
    ]);
    await tester.pump();
    expect(find.text('popup-B'), findsOneWidget);
    expect(find.text('side-A'), findsNothing);
    expect(tester.takeException(), isNull);
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
    final requests = <Completer<List<ReadTheme>>>[];

    Future<List<ReadTheme>> loadThemes() {
      attempts++;
      final request = Completer<List<ReadTheme>>();
      requests.add(request);
      return request.future;
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
    requests.single.completeError(StateError('private database detail'));
    await tester.pump();

    expect(
      find.text("Content couldn't be loaded. Try again."),
      findsOneWidget,
    );
    expect(find.textContaining('private database detail'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    requests[1].complete(const <ReadTheme>[]);
    await tester.pump();

    expect(attempts, 2);
    expect(find.text('style-panel'), findsOneWidget);

    await tester.tap(find.text('Background'));
    await tester.pump();

    expect(find.text('background-panel'), findsOneWidget);
    expect(find.text('style-panel'), findsNothing);

    final backTooltip = MaterialLocalizations.of(
      tester.element(find.byType(ReadingToolPanel)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pump();

    expect(find.text('style-panel'), findsOneWidget);
    expect(find.text('background-panel'), findsNothing);
    expect(attempts, 2);
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

  testWidgets('late success from an earlier style request cannot replace B',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    final requestA = Completer<List<ReadTheme>>();
    final requestB = Completer<List<ReadTheme>>();
    final requests = <Completer<List<ReadTheme>>>[requestA, requestB];
    var attempts = 0;

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        notesBuilder: (context) => const Text('notes-panel'),
        styleThemesLoader: () => requests[attempts++].future,
        styleBuilder: (context, themes, setCurrentPage) =>
            Text(themes.isEmpty ? 'style-B' : 'style-A'),
      ),
    );

    kind.value = ReadingToolPanelKind.notes;
    await tester.pump();
    kind.value = ReadingToolPanelKind.style;
    await tester.pump();

    requestB.complete(const <ReadTheme>[]);
    await tester.pump();
    await tester.pump();
    expect(find.text('style-B'), findsOneWidget);

    requestA.complete(<ReadTheme>[
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

  testWidgets('late failure from an earlier style request cannot replace B',
      (tester) async {
    final kind = ValueNotifier(ReadingToolPanelKind.style);
    addTearDown(kind.dispose);
    final requestA = Completer<List<ReadTheme>>();
    final requestB = Completer<List<ReadTheme>>();
    final requests = <Completer<List<ReadTheme>>>[requestA, requestB];
    var attempts = 0;

    await pumpDesignSystem(
      tester,
      _host(
        kind: kind,
        notesBuilder: (context) => const Text('notes-panel'),
        styleThemesLoader: () => requests[attempts++].future,
        styleBuilder: (context, themes, setCurrentPage) =>
            const Text('style-B'),
      ),
    );

    kind.value = ReadingToolPanelKind.notes;
    await tester.pump();
    kind.value = ReadingToolPanelKind.style;
    await tester.pump();

    requestB.complete(const <ReadTheme>[]);
    await tester.pump();
    await tester.pump();
    expect(find.text('style-B'), findsOneWidget);

    requestA.completeError(StateError('stale private failure'));
    await tester.pump();

    expect(find.text('style-B'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.textContaining('stale private failure'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[
    const Size(320, 640),
    const Size(640, 360),
    const Size(800, 1200),
  ]) {
    testWidgets(
        'real background selector enters and returns without overflow at '
        '${size.width}x${size.height}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final kind = ValueNotifier(ReadingToolPanelKind.style);
      addTearDown(kind.dispose);

      final container = ProviderContainer(
        overrides: [bgimgProvider.overrideWith(_EmptyBgimg.new)],
      );
      addTearDown(container.dispose);

      await pumpDesignSystem(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: Column(
            children: [
              const Spacer(),
              _host(
                kind: kind,
                styleBuilder: (context, themes, setCurrentPage) => AppButton(
                  label: 'Background',
                  onPressed: () => setCurrentPage(const BgimgSelector()),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Background'));
      await tester.pump();

      expect(find.byType(BgimgSelector), findsOneWidget);
      expect(tester.takeException(), isNull);
      final panelRect = tester.getRect(find.byType(BottomSheet));
      final listRect = tester.getRect(
        find.descendant(
          of: find.byType(BgimgSelector),
          matching: find.byType(ListView),
        ),
      );
      expect(
        panelRect.height,
        lessThanOrEqualTo(math.min(size.height * 0.7, 600.0) + 1),
      );
      expect(listRect.bottom, lessThanOrEqualTo(panelRect.bottom + 1));
      expect(listRect.height, lessThanOrEqualTo(panelRect.height));

      final backTooltip = MaterialLocalizations.of(
        tester.element(find.byType(ReadingToolPanel)),
      ).backButtonTooltip;
      await tester.tap(find.byTooltip(backTooltip));
      await tester.pump();

      expect(find.text('Background'), findsOneWidget);
      expect(find.byType(BgimgSelector), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in <Size>[const Size(320, 640), const Size(1200, 800)]) {
    testWidgets(
        'long scrolling content stays bounded at ${size.width}x${size.height}',
        (tester) async {
      final view = tester.view;
      view.physicalSize = size;
      view.devicePixelRatio = 1.0;
      addTearDown(view.reset);
      final kind = ValueNotifier(ReadingToolPanelKind.style);
      addTearDown(kind.dispose);

      await pumpDesignSystem(
        tester,
        Column(
          children: [
            const Spacer(),
            _host(
              kind: kind,
              styleBuilder: (context, themes, setCurrentPage) =>
                  SingleChildScrollView(
                child: Column(
                  children: List.generate(
                    80,
                    (index) => SizedBox(
                      height: 24,
                      child: Text('long-style-row-$index'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);
      final viewportHeight = tester.getSize(scrollable).height;
      expect(viewportHeight, lessThan(size.height));
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(size.height),
      );
      expect(
        tester
            .widget<Scrollable>(scrollable)
            .controller!
            .position
            .maxScrollExtent,
        greaterThan(0),
      );

      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pump();
      expect(find.text('long-style-row-79'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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
