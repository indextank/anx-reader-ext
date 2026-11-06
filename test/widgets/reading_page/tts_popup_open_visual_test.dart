import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/tts_playback_provider.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/tts_panel_controller.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/design_system_test_utils.dart';

const TtsPlaybackCursor _cursor = TtsPlaybackCursor(
  utteranceId: 'p1#0',
  charOffset: 7,
  paragraphCharOffset: 0,
);

TtsPlaybackState _state({required TtsPlaybackPhase phase}) {
  return TtsPlaybackState(
    phase: phase,
    engine: TtsEngineKind.system,
    sessionId: 1,
    rate: 0.6,
    cursor: _cursor,
  );
}

class _FakeController implements TtsPanelController {
  _FakeController(this.initial)
      : stateListenable = ValueNotifier<TtsPlaybackState>(initial);

  final TtsPlaybackState initial;

  @override
  final ValueNotifier<TtsPlaybackState> stateListenable;

  int playCount = 0;

  @override
  double get rate => stateListenable.value.rate;

  @override
  double get volume => 1;

  @override
  double get pitch => 1;

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> changeRate(double rate) async {}

  @override
  Future<void> switchEngine(String serviceId) async {}

  @override
  Future<void> playPrevious() async {}

  @override
  Future<void> playNext() async {}

  @override
  void setVolume(double volume) {}

  @override
  void setPitch(double pitch) {}
}

ReadingToolPanel _panel({required WidgetBuilder ttsBuilder}) {
  return ReadingToolPanel(
    kind: ReadingToolPanelKind.tts,
    notesBuilder: (_) => const SizedBox.shrink(),
    ttsBuilder: ttsBuilder,
    styleThemesLoader: () async => const [],
    styleBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ReadingToolPanel panel,
) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpDesignSystem(
    tester,
    panel,
    theme: AppTheme.build(
      brightness: Brightness.dark,
      seedColor: AppColors.defaultBrand,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ttsService': 'system',
      'ttsRate': 0.6,
      'ttsVolume': 1.0,
      'ttsPitch': 1.0,
    });
    await Prefs().initPrefs();
  });

  group('popup TTS panel size', () {
    testWidgets(
        'does not collapse to the intrinsic width of a loading card '
        '(the reported white capsule)', (tester) async {
      final never = Completer<void>();
      await _pumpPanel(
        tester,
        _panel(
          ttsBuilder: (_) => TtsSessionGate(
            initialize: () => never.future,
            builder: (_) => const Text('controls'),
          ),
        ),
      );

      final surface = find.byKey(readingToolPanelSurfaceKey);
      expect(surface, findsOneWidget);
      final size = tester.getSize(surface);
      // 1000px wide window: panel is capped at 600. The old implementation
      // shrink-wrapped to the loading card's ~32px intrinsic width.
      expect(size.width, 600);
      expect(size.height, greaterThan(200));
    });

    testWidgets('width is deterministic for zero-intrinsic-width content',
        (tester) async {
      await _pumpPanel(
        tester,
        _panel(ttsBuilder: (_) => const SizedBox(height: 240)),
      );
      final surface = find.byKey(readingToolPanelSurfaceKey);
      expect(tester.getSize(surface).width, 600);
    });

    testWidgets('width stays stable across playback state changes',
        (tester) async {
      final controller = _FakeController(_state(phase: TtsPlaybackPhase.idle));
      await _pumpPanel(
        tester,
        _panel(
          ttsBuilder: (_) => ProviderScope(
            overrides: [
              ttsPanelControllerProvider.overrideWithValue(controller),
            ],
            child: TtsWidget(epubPlayerKey: GlobalKey<EpubPlayerState>()),
          ),
        ),
      );
      final surface = find.byKey(readingToolPanelSurfaceKey);
      final before = tester.getSize(surface);

      controller.stateListenable.value = _state(
        phase: TtsPlaybackPhase.playing,
      );
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(surface).width, before.width);
      expect(tester.getSize(surface).width, 600);
      expect(tester.takeException(), isNull);
    });
  });

  group('TTS panel panel-open rendering', () {
    testWidgets(
        'paints transport controls on the first frame, never a loading '
        'skeleton/card', (tester) async {
      final controller = _FakeController(_state(phase: TtsPlaybackPhase.idle));
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [
            ttsPanelControllerProvider.overrideWithValue(controller),
          ],
          child: TtsWidget(epubPlayerKey: GlobalKey<EpubPlayerState>()),
        ),
        theme: AppTheme.build(
          brightness: Brightness.dark,
          seedColor: AppColors.defaultBrand,
        ),
      );

      // First content frame: controls are already there (no blocking skeleton
      // and no loading Card that used to collapse into a white block).
      expect(find.byType(AppSkeleton), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(TtsWidget), findsOneWidget);
      expect(find.byIcon(EvaIcons.stop_circle_outline), findsOneWidget);
      expect(find.byIcon(EvaIcons.chevron_right), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });
}
