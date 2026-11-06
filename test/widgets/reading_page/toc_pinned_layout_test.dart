// ReadingPage floating / pinned TOC layout integration tests.
//
// Scope of this file: the production [ReadingPage] wiring of the TOC pin
// feature. The floating TOC is hosted by the reading page Scaffold drawer; the
// pinned TOC is a left sidebar inside the body Row. TOC content is injected
// through a test-side provider override so loading / error / empty / data can
// be exercised without a real EpubPlayer.
//
// Only this test file is added for the integration-test part of the feature.
// The harness mirrors test/widgets/reading_page/reading_page_panel_integration_test.dart
// (prefs, plugin fakes, l10n delegates, production reader stage).

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' as app;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/reading_page/toc_pin_button.dart';
import 'package:anx_reader/widgets/reading_page/toc_sidebar.dart';
import 'package:anx_reader/widgets/reading_page/toc_widget.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// Transitive platform interface is used only for the wakelock test double.
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeAudioHandler implements AudioHandler {
  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _ReadingPageHarness {
  final pageKey = GlobalKey<ReadingPageState>();
  final book = Book.mock();
}

/// Test-side TOC content source.
///
/// `tocContentProvider` is overridden to watch this provider, so every test can
/// inject loading / error / empty / data without starting an EpubPlayer.
final _tocStateProvider = StateProvider<AsyncValue<List<TocItem>>>(
  (ref) => const AsyncValue.data(<TocItem>[]),
);

TocItem _tocItem({
  required String id,
  required String label,
  List<TocItem> subitems = const <TocItem>[],
  int level = 0,
}) {
  return TocItem(
    id: id,
    href: '$id.xhtml',
    label: label,
    subitems: subitems,
    level: level,
    startPage: 0,
    startPercentage: 0.0,
  );
}

List<TocItem> _nestedTocItems() {
  return <TocItem>[
    _tocItem(
      id: 'ch1',
      label: 'Chapter 1',
      subitems: <TocItem>[
        _tocItem(id: 'ch1-1', label: 'Chapter 1.1', level: 1),
        _tocItem(id: 'ch1-2', label: 'Chapter 1.2', level: 1),
      ],
    ),
    _tocItem(id: 'ch2', label: 'Chapter 2'),
  ];
}

List<TocItem> _deepTocItems() {
  return <TocItem>[
    _tocItem(
      id: 'l1',
      label: 'Level 1',
      subitems: <TocItem>[
        _tocItem(
          id: 'l1-1',
          label: 'Level 1.1',
          level: 1,
          subitems: <TocItem>[
            _tocItem(id: 'l1-1-1', label: 'Level 1.1.1', level: 2),
          ],
        ),
      ],
    ),
  ];
}

/// 模拟"目录搜索进行中"的状态（不启动真实书页搜索）。
class _ActiveTocSearch extends TocSearch {
  @override
  TocSearchState build() => const TocSearchState(query: 'chapter');
}

Future<_ReadingPageHarness> _pumpReadingPage(
  WidgetTester tester, {
  Map<String, Object> initialPrefs = const <String, Object>{},
  Size viewSize = const Size(1000, 800),
  TextScaler? textScaler,
  List<Override> extraOverrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'openBookAnimation': false,
    'hideStatusBar': false,
    ...initialPrefs,
  });
  await Prefs().initPrefs();
  Prefs().panelPositionWriterForTesting = null;
  app.audioHandler = _FakeAudioHandler();
  wakelockPlusPlatformInstance = _FakeWakelock();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => 'test-documents',
  );
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => Prefs().panelPositionWriterForTesting = null);

  final harness = _ReadingPageHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...extraOverrides,
        tocContentProvider.overrideWith((ref) => ref.watch(_tocStateProvider)),
      ],
      child: MaterialApp(
        navigatorKey: app.navigatorKey,
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
          eInkMode: false,
        ),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: textScaler),
                  child: child!,
                ),
        home: ReadingPage(
          key: harness.pageKey,
          book: harness.book,
          heroTag: 'toc-pinned-layout-test',
          initialThemes: const [],
          readerBuilder: (_) => const Text('production-reader'),
          notesBuilder: (_) => const Text('production-notes'),
          ttsBuilder: (_) => const Text('production-tts'),
          styleThemesLoader: () async => const [],
          readingTimeSaver: (readingTime, startedAt) async {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  return harness;
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(ReadingPage)),
    listen: false,
  );
}

void _setTocState(WidgetTester tester, AsyncValue<List<TocItem>> state) {
  _container(tester).read(_tocStateProvider.notifier).state = state;
}

void _setPinned(WidgetTester tester, bool pinned) {
  _container(tester).read(tocPinnedProvider.notifier).setPinned(pinned);
}

L10n _l10n(WidgetTester tester) {
  return L10n.of(tester.element(find.byType(ReadingPage)));
}

/// Advances the drawer / pin transition animations until they are settled.
///
/// The drawer animation is ~246ms; the extra frames also flush the post-frame
/// callback that reopens the floating drawer after unpinning.
Future<void> _pumpLayoutSettled(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openFloatingToc(
  WidgetTester tester,
  _ReadingPageHarness harness,
) async {
  await harness.pageKey.currentState!.tocHandler();
  await _pumpLayoutSettled(tester);
  expect(find.byType(Drawer), findsOneWidget);
  expect(find.byKey(tocFloatingPanelKey), findsOneWidget);
}

Future<void> _pinFromFloatingToc(WidgetTester tester) async {
  await tester.tap(find.byKey(tocPinButtonKey));
  await _pumpLayoutSettled(tester);
  expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
}

/// Unpins through the sidebar pin button and re-pins through the reopened
/// floating drawer, asserting both transitions render the TOC safely.
Future<void> _expectPinToggleRoundTrip(WidgetTester tester) async {
  expect(find.byKey(tocPinButtonKey), findsOneWidget);
  await tester.tap(find.byKey(tocPinButtonKey));
  await _pumpLayoutSettled(tester);
  expect(find.byKey(tocPinnedSidebarKey), findsNothing);
  expect(find.byType(Drawer), findsOneWidget);

  expect(find.byKey(tocPinButtonKey), findsOneWidget);
  await tester.tap(find.byKey(tocPinButtonKey));
  await _pumpLayoutSettled(tester);
  expect(find.byType(Drawer), findsNothing);
  expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
}

void _expectInsidePinnedSidebar(Key key) {
  expect(
    find.descendant(
      of: find.byKey(tocPinnedSidebarKey),
      matching: find.byKey(key),
    ),
    findsOneWidget,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unpinned TOC opens as a floating drawer and outside tap closes it',
      (tester) async {
    final harness = await _pumpReadingPage(tester);

    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(find.text('production-reader'), findsOneWidget);

    await _openFloatingToc(tester, harness);
    expect(find.byKey(tocFloatingPanelKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsNothing);
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(tester.takeException(), isNull);

    // Tapping the body outside the drawer (on the drawer scrim) closes it.
    await tester.tapAt(const Offset(900, 400));
    await _pumpLayoutSettled(tester);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinning from the floating drawer replaces it with the sidebar',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final l10n = _l10n(tester);
    await _openFloatingToc(tester, harness);

    await _pinFromFloatingToc(tester);

    // The floating drawer (and therefore its modal scrim) is gone.
    // Note: find.byType(ModalBarrier) is not usable here because every
    // ModalRoute (including MaterialApp.home) keeps its own barrier overlay
    // entry; the drawer scrim is built by the DrawerController itself, so an
    // absent Drawer proves there is no floating scrim.
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);

    // Exactly one pinned sidebar hosting exactly one TOC panel.
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.byType(TocWidget), findsOneWidget);
    expect(tester.getSize(find.byKey(tocPinnedSidebarKey)).width, 320);

    // The reader stage is still mounted to the right of the sidebar.
    expect(find.text('production-reader'), findsOneWidget);
    expect(tester.getCenter(find.text('production-reader')).dx,
        greaterThan(320));

    // Pin button now shows the locked state and its "unpin" tooltip.
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(tocPinButtonKey),
        matching: find.byIcon(Icons.lock),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_open), findsNothing);
    expect(find.byTooltip(l10n.readingTocUnpin), findsOneWidget);

    // While pinned, opening the floating TOC via the handler is a no-op.
    await harness.pageKey.currentState!.tocHandler();
    await tester.pump();
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned sidebar keeps expanded TOC state across page-turn rebuilds',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final l10n = _l10n(tester);

    _setTocState(tester, AsyncValue.data(_nestedTocItems()));
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 1.1'), findsNothing);

    final expandButton = find.descendant(
      of: find.byKey(tocPinnedSidebarKey),
      matching: find.byTooltip(l10n.readingTocExpand),
    );
    expect(expandButton, findsOneWidget);
    await tester.tap(expandButton);
    await tester.pump();
    expect(find.text('Chapter 1.1'), findsOneWidget);
    expect(find.text('Chapter 1.2'), findsOneWidget);

    // Simulate several page turns: parent rebuilds must not rebuild the sidebar
    // state away.
    for (var i = 0; i < 3; i++) {
      // ignore: invalid_use_of_protected_member
      harness.pageKey.currentState!.setState(() {});
      await tester.pump();
    }
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.text('Chapter 1.1'), findsOneWidget);
    expect(find.text('Chapter 1.2'), findsOneWidget);

    // Tapping the reader must not hide / duplicate the pinned TOC either.
    await tester.tapAt(tester.getCenter(find.text('production-reader')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Chapter 1.1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unpinning the sidebar reopens the floating drawer with pin cleared',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final l10n = _l10n(tester);
    await _openFloatingToc(tester, harness);
    await _pinFromFloatingToc(tester);

    await tester.tap(find.byKey(tocPinButtonKey));
    await _pumpLayoutSettled(tester);

    // Sidebar is gone, floating drawer reopened automatically.
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(find.byKey(tocPinnedPanelKey), findsNothing);
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.byKey(tocFloatingPanelKey), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(find.byTooltip(l10n.readingTocPin), findsOneWidget);
    expect(_container(tester).read(tocPinnedProvider), isFalse);

    // Tapping outside closes the reopened drawer; the pin stays cleared.
    await tester.tapAt(const Offset(900, 400));
    await _pumpLayoutSettled(tester);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(_container(tester).read(tocPinnedProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid pin taps settle to one deterministic layout', (tester) async {
    final harness = await _pumpReadingPage(tester);
    await _openFloatingToc(tester, harness);

    // Three toggles dispatched before any frame in between: odd count => pinned.
    await tester.tap(find.byKey(tocPinButtonKey));
    await tester.tap(find.byKey(tocPinButtonKey));
    await tester.tap(find.byKey(tocPinButtonKey));
    await _pumpLayoutSettled(tester);

    expect(_container(tester).read(tocPinnedProvider), isTrue);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.byType(TocWidget), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(tocPinButtonKey),
        matching: find.byIcon(Icons.lock),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned sidebar width is responsive and always leaves the reader',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);

    // Wide window: fixed 320px sidebar plus a live reader stage.
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(tester.getSize(find.byKey(tocPinnedSidebarKey)).width, 320);
    expect(find.text('production-reader'), findsOneWidget);
    expect(tester.getSize(find.text('production-reader')).width, greaterThan(0));
    expect(tester.takeException(), isNull);

    // Narrow window: the sidebar is capped at 45% so the reader always exists.
    tester.view.physicalSize = const Size(380, 700);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    final narrowWidth = tester.getSize(find.byKey(tocPinnedSidebarKey)).width;
    expect(narrowWidth, lessThanOrEqualTo(380 * 0.45));
    expect(find.text('production-reader'), findsOneWidget);
    expect(tester.getSize(find.text('production-reader')).width, greaterThan(0));
    expect(tester.takeException(), isNull);

    // The pinned state survives the resize.
    expect(_container(tester).read(tocPinnedProvider), isTrue);
    expect(harness.pageKey.currentState, isNotNull);
  });

  testWidgets('pinned sidebar renders loading/error/empty and keeps pin working',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final l10n = _l10n(tester);
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);

    // loading
    _setTocState(tester, const AsyncValue<List<TocItem>>.loading());
    await tester.pump();
    _expectInsidePinnedSidebar(tocLoadingStateKey);
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    await _expectPinToggleRoundTrip(tester);
    _expectInsidePinnedSidebar(tocLoadingStateKey);

    // error + retry entry
    _setTocState(
      tester,
      AsyncValue<List<TocItem>>.error(
        const TocLoadFailure(),
        StackTrace.empty,
      ),
    );
    await tester.pump();
    _expectInsidePinnedSidebar(tocErrorStateKey);
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    expect(find.text(l10n.commonRetry), findsOneWidget);
    await tester.tap(find.text(l10n.commonRetry));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The injected error is still the provider value; retry must only run the
    // reading page callback path, not crash.
    expect(find.byKey(tocErrorStateKey), findsOneWidget);
    await _expectPinToggleRoundTrip(tester);
    _expectInsidePinnedSidebar(tocErrorStateKey);

    // empty
    _setTocState(tester, const AsyncValue.data(<TocItem>[]));
    await tester.pump();
    _expectInsidePinnedSidebar(tocEmptyStateKey);
    expect(find.byKey(tocPinButtonKey), findsOneWidget);
    await _expectPinToggleRoundTrip(tester);
    _expectInsidePinnedSidebar(tocEmptyStateKey);

    expect(harness.pageKey.currentState, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned sidebar survives tapping a chapter in the TOC',
      (tester) async {
    await _pumpReadingPage(tester);

    _setTocState(tester, AsyncValue.data(_nestedTocItems()));
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);

    // Tapping a chapter in the pinned TOC (jump to chapter) must not close
    // the pinned sidebar: the reading page makes closeDrawer a no-op.
    await tester.tap(find.text('Chapter 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned state survives pushing and returning from another route',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);

    // Push a route over the reading page, then return: the pinned TOC must
    // survive the route round-trip (provider is keepAlive, page not disposed).
    final navigator = Navigator.of(tester.element(find.byType(ReadingPage)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('detail-route')),
      ),
    );
    await _pumpLayoutSettled(tester);
    expect(find.text('detail-route'), findsOneWidget);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);

    navigator.pop();
    await _pumpLayoutSettled(tester);
    expect(harness.pageKey.currentState, isNotNull);
    expect(_container(tester).read(tocPinnedProvider), isTrue);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.text('production-reader'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned TOC list and reader area scroll independently',
      (tester) async {
    await _pumpReadingPage(tester);
    final manyItems = <TocItem>[
      for (var i = 1; i <= 40; i++)
        _tocItem(id: 'scroll-$i', label: 'Scroll chapter $i'),
    ];
    _setTocState(tester, AsyncValue.data(manyItems));
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);

    // Scrolling the TOC list must not hide/remove the pinned sidebar, and the
    // reader stage must stay mounted to the right.
    await tester.drag(
      find.descendant(
        of: find.byKey(tocPinnedSidebarKey),
        matching: find.byType(ScrollablePositionedList),
      ),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byKey(tocPinnedPanelKey), findsOneWidget);
    expect(find.text('production-reader'), findsOneWidget);
    expect(_container(tester).read(tocPinnedProvider), isTrue);

    // Interactions in the reader area keep the TOC pinned as well.
    await tester.drag(
      find.text('production-reader'),
      const Offset(0, 200),
    );
    await tester.pump();
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned sidebar stays overflow-free on very narrow viewports',
      (tester) async {
    // 240/300 dp viewports are below the typical phone minimum but the spec
    // requires the pinned layout to never overflow. The TOC must switch to its
    // compact arrangement instead of hitting ListTile/SearchBar layout errors.
    for (final size in const <Size>[
      Size(240, 400),
      Size(300, 600),
    ]) {
      final harness = await _pumpReadingPage(tester, viewSize: size);
      _setTocState(tester, AsyncValue.data(_nestedTocItems()));
      _setPinned(tester, true);
      await _pumpLayoutSettled(tester);

      expect(find.byKey(tocPinnedSidebarKey), findsOneWidget,
          reason: 'pinned sidebar missing at ${size.width}');
      final sidebarWidth =
          tester.getSize(find.byKey(tocPinnedSidebarKey)).width;
      expect(sidebarWidth, lessThanOrEqualTo(size.width * 0.45 + 1e-9),
          reason: 'sidebar must leave room for the reader at ${size.width}');
      expect(sidebarWidth, greaterThan(0));
      expect(find.text('Chapter 1'), findsOneWidget,
          reason: 'TOC list must render at ${size.width}');
      expect(find.text('production-reader'), findsOneWidget,
          reason: 'reader stage must survive at ${size.width}');
      expect(tester.takeException(), isNull,
          reason: 'no layout overflow at ${size.width}x${size.height}');
      expect(harness.pageKey.currentState, isNotNull);
    }
  });

  testWidgets('pinned empty/error states stay overflow-free at 300dp',
      (tester) async {
    final harness = await _pumpReadingPage(
      tester,
      viewSize: const Size(300, 600),
    );
    _setPinned(tester, true);
    await _pumpLayoutSettled(tester);
    expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);

    _setTocState(tester, const AsyncValue.data(<TocItem>[]));
    await tester.pump();
    _expectInsidePinnedSidebar(tocEmptyStateKey);
    expect(tester.takeException(), isNull);

    _setTocState(
      tester,
      AsyncValue<List<TocItem>>.error(
        const TocLoadFailure(),
        StackTrace.empty,
      ),
    );
    await tester.pump();
    _expectInsidePinnedSidebar(tocErrorStateKey);
    expect(tester.takeException(), isNull);
    expect(harness.pageKey.currentState, isNotNull);
  });

  testWidgets('deep expanded TOC stays overflow-free at large text scales',
      (tester) async {
    // Regression: nested/expanded TOC items at accessibility text scales used
    // to trigger ListTile's "Trailing widget consumes the entire tile width".
    for (final scale in <double>[1.3, 1.5]) {
      await _pumpReadingPage(
        tester,
        viewSize: const Size(360, 640),
        textScaler: TextScaler.linear(scale),
      );
      _setTocState(tester, AsyncValue.data(_deepTocItems()));
      _setPinned(tester, true);
      await _pumpLayoutSettled(tester);
      expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);

      final l10n = _l10n(tester);
      final expandTooltip = find.descendant(
        of: find.byKey(tocPinnedSidebarKey),
        matching: find.byTooltip(l10n.readingTocExpand),
      );
      await tester.tap(expandTooltip.first);
      await tester.pump();
      final nestedExpand = find.descendant(
        of: find.byKey(tocPinnedSidebarKey),
        matching: find.byTooltip(l10n.readingTocExpand),
      );
      if (nestedExpand.evaluate().isNotEmpty) {
        await tester.tap(nestedExpand.first);
        await tester.pump();
      }

      expect(tester.takeException(), isNull,
          reason: 'pinned TOC overflowed at text scale $scale');
      expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('active TOC search stays overflow-free in compact pinned sidebar',
      (tester) async {
    // Regression: with search active the SearchBar trailing clear button used
    // to overflow in the narrow pinned sidebar (<= 300dp viewport).
    for (final size in const <Size>[Size(240, 400), Size(300, 600)]) {
      await _pumpReadingPage(
        tester,
        viewSize: size,
        extraOverrides: <Override>[
          tocSearchProvider.overrideWith(() => _ActiveTocSearch()),
        ],
      );
      _setPinned(tester, true);
      await _pumpLayoutSettled(tester);
      expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
      expect(find.byType(SearchBar), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'active TOC search overflowed at ${size.width}');
      expect(find.byKey(tocPinnedSidebarKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('floating drawer renders TOC async states consistently',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final l10n = _l10n(tester);
    await _openFloatingToc(tester, harness);

    // empty
    _setTocState(tester, const AsyncValue.data(<TocItem>[]));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byKey(tocEmptyStateKey),
      ),
      findsOneWidget,
    );

    // error + retry
    _setTocState(
      tester,
      AsyncValue<List<TocItem>>.error(
        const TocLoadFailure(),
        StackTrace.empty,
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byKey(tocErrorStateKey),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.commonRetry), findsOneWidget);
    await tester.tap(find.text(l10n.commonRetry));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(tocErrorStateKey), findsOneWidget);

    // loading
    _setTocState(tester, const AsyncValue<List<TocItem>>.loading());
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byKey(tocLoadingStateKey),
      ),
      findsOneWidget,
    );

    // The drawer stays closeable through the scrim in every state.
    await tester.tapAt(const Offset(900, 400));
    await _pumpLayoutSettled(tester);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byKey(tocFloatingPanelKey), findsNothing);
    expect(find.byKey(tocPinnedSidebarKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
