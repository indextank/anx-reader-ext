import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' as app;
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/reading_page/reading_panel_coordinator.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// Transitive platform interface is used only by this plugin test double.
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

class _FakeAiHistoryNotifier
    extends StateNotifier<AsyncValue<List<AiChatHistoryEntry>>>
    implements AiHistoryNotifier {
  _FakeAiHistoryNotifier() : super(const AsyncValue.data([]));

  @override
  Future<void> refresh() async {}

  @override
  Future<void> clear() async {
    state = const AsyncValue.data([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadingPageHarness {
  final pageKey = GlobalKey<ReadingPageState>();
  final book = Book.mock();
  var ttsBuilds = 0;

  ReadingPanelCoordinatorState get coordinator =>
      pageKey.currentState!.panelCoordinatorKeyForTesting.currentState!;
}

Future<_ReadingPageHarness> _pumpReadingPage(
  WidgetTester tester, {
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'openBookAnimation': false,
    'hideStatusBar': false,
    ...initialPrefs,
  });
  await Prefs().initPrefs();
  Prefs().panelPositionWriterForTesting = null;
  audioHandler = _FakeAudioHandler();
  wakelockPlusPlatformInstance = _FakeWakelock();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => 'test-documents',
  );
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => Prefs().panelPositionWriterForTesting = null);

  final harness = _ReadingPageHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiHistoryProvider.overrideWith((ref) => _FakeAiHistoryNotifier()),
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
        home: ReadingPage(
          key: harness.pageKey,
          book: harness.book,
          heroTag: 'production-test',
          initialThemes: const [],
          readerBuilder: (_) => const Text('production-reader'),
          notesBuilder: (_) => const Text('production-notes'),
          ttsBuilder: (_) {
            harness.ttsBuilds++;
            return const Text('production-tts');
          },
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

Future<void> _openProductionTool(
  WidgetTester tester,
  _ReadingPageHarness harness,
  String tooltip,
) async {
  final l10n = L10n.of(tester.element(find.byType(ReadingPage)));
  if (tooltip == l10n.navBarNotes) {
    harness.pageKey.currentState!.noteHandler();
  } else if (tooltip == l10n.ttsNarrator) {
    harness.pageKey.currentState!.ttsHandler();
  } else {
    harness.pageKey.currentState!.styleHandler();
  }
  await tester.pump();
}

Future<void> _openProductionAi(
  WidgetTester tester,
  _ReadingPageHarness harness,
) async {
  await harness.pageKey.currentState!.showAiChat();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production ReadingPage applies an async position success',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final prefs = Prefs();
    final l10n = L10n.of(tester.element(find.byType(ReadingPage)));
    final write = Completer<bool>();
    prefs.panelPositionWriterForTesting = (key, value) => write.future;

    await _openProductionTool(tester, harness, l10n.navBarNotes);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(harness.coordinator.activeTool, isNotNull);

    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    await tester.pump();
    expect(find.byType(ReadingSidePanelHost), findsNothing);

    write.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ReadingSidePanelHost), findsNothing);
    await tester.pump();

    expect(find.byType(ReadingSidePanelHost), findsOneWidget);
    expect(find.text('production-notes'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('production ReadingPage applies async failure fallback',
      (tester) async {
    final harness = await _pumpReadingPage(
      tester,
      initialPrefs: {'notesPanelPosition': 'right'},
    );
    final prefs = Prefs();
    final l10n = L10n.of(tester.element(find.byType(ReadingPage)));
    final write = Completer<bool>();
    prefs.panelPositionWriterForTesting = (key, value) => write.future;

    await _openProductionTool(tester, harness, l10n.navBarNotes);
    expect(find.byType(ReadingSidePanelHost), findsOneWidget);

    prefs.notesPanelPosition = AiPanelPositionEnum.popup;
    write.complete(false);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ReadingSidePanelHost), findsNothing);
    await tester.pump();

    expect(find.byType(ReadingSidePanelHost), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('production-notes'), findsOneWidget);
  });

  testWidgets('production ReadingPage follows only the latest rapid write',
      (tester) async {
    final harness = await _pumpReadingPage(tester);
    final prefs = Prefs();
    final l10n = L10n.of(tester.element(find.byType(ReadingPage)));
    final writes = <Completer<bool>>[];
    prefs.panelPositionWriterForTesting = (key, value) {
      final write = Completer<bool>();
      writes.add(write);
      return write.future;
    };

    await _openProductionTool(tester, harness, l10n.navBarNotes);
    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    prefs.notesPanelPosition = AiPanelPositionEnum.popup;
    await tester.pump();
    expect(writes, hasLength(1));

    writes[0].complete(true);
    await tester.pump();
    await tester.pump();
    expect(writes, hasLength(2));
    expect(find.byType(ReadingSidePanelHost), findsNothing);

    writes[1].complete(true);
    await tester.pump();
    await tester.pump();

    expect(find.byType(ReadingSidePanelHost), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('production-notes'), findsOneWidget);
  });

  testWidgets('production split AI is replaced by popup without duplicate key',
      (tester) async {
    final harness = await _pumpReadingPage(
      tester,
      initialPrefs: {'aiChatDisplayMode': 'split'},
    );
    await _openProductionAi(tester, harness);
    expect(find.byType(ReadingSidePanelHost), findsOneWidget);
    expect(find.byType(AiChatStream), findsOneWidget);
    harness.pageKey.currentState!.aiChatKey.currentState!.inputController.text =
        'draft-before-popup';

    Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
    unawaited(
      harness.pageKey.currentState!.showAiChat(content: 'popup-message'),
    );
    await tester.pump();

    expect(find.byType(ReadingSidePanelHost), findsNothing);
    expect(find.byType(ModalBottomSheetRoute), findsNothing);
    expect(find.byType(AiChatStream), findsOneWidget);
    expect(
      harness
          .pageKey.currentState!.aiChatKey.currentState!.inputController.text,
      'draft-before-popup',
    );
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(AiChatStream))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.coordinator.activeTool, isNull);
    expect(find.byType(AiChatStream), findsNothing);
  });

  testWidgets('production notes and TTS are replaced before AI popup',
      (tester) async {
    final harness = await _pumpReadingPage(
      tester,
      initialPrefs: {'aiChatDisplayMode': 'popup'},
    );
    final l10n = L10n.of(tester.element(find.byType(ReadingPage)));

    await _openProductionTool(tester, harness, l10n.navBarNotes);
    expect(find.byType(BottomSheet), findsOneWidget);
    unawaited(
      harness.pageKey.currentState!.showAiChat(content: 'from-notes'),
    );
    await tester.pump();

    expect(find.text('production-notes'), findsNothing);
    expect(find.byKey(const ValueKey('reading-tool-panel')), findsNothing);
    expect(find.byType(AiChatStream), findsOneWidget);
    expect(harness.coordinator.activeTool, isNull);
    Navigator.of(tester.element(find.byType(AiChatStream))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _openProductionTool(tester, harness, l10n.ttsNarrator);
    expect(find.text('production-tts'), findsOneWidget);
    unawaited(
      harness.pageKey.currentState!.showAiChat(content: 'from-tts'),
    );
    await tester.pump();

    expect(find.text('production-tts'), findsNothing);
    expect(find.byKey(const ValueKey('reading-tool-panel')), findsNothing);
    expect(find.byType(AiChatStream), findsOneWidget);
    expect(harness.coordinator.activeTool, isNull);
    expect(tester.takeException(), isNull);
  });
}
