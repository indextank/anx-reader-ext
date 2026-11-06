import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/tts_playback_provider.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
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

TtsPlaybackState _state({
  required TtsPlaybackPhase phase,
  int sessionId = 1,
  double rate = 0.6,
  TtsPlaybackCursor? cursor,
  TtsPlaybackError? error,
}) {
  return TtsPlaybackState(
    phase: phase,
    engine: TtsEngineKind.system,
    sessionId: sessionId,
    rate: rate,
    cursor: cursor,
    error: error,
  );
}

class FakeTtsPanelController implements TtsPanelController {
  FakeTtsPanelController(TtsPlaybackState initial)
      : stateListenable = ValueNotifier<TtsPlaybackState>(initial);

  @override
  final ValueNotifier<TtsPlaybackState> stateListenable;

  final List<double> rateChanges = <double>[];
  final List<double> volumeChanges = <double>[];
  final List<double> pitchChanges = <double>[];

  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int retryCount = 0;
  int previousCount = 0;
  int nextCount = 0;

  double _volume = 1.0;
  double _pitch = 1.0;

  TtsPlaybackState get state => stateListenable.value;

  void emit(TtsPlaybackState value) => stateListenable.value = value;

  @override
  double get rate => state.rate;

  @override
  double get volume => _volume;

  @override
  double get pitch => _pitch;

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> retry() async {
    retryCount++;
  }

  @override
  Future<void> changeRate(double rate) async {
    rateChanges.add(rate);
  }

  @override
  Future<void> switchEngine(String serviceId) async {}

  @override
  Future<void> playPrevious() async {
    previousCount++;
  }

  @override
  Future<void> playNext() async {
    nextCount++;
  }

  @override
  void setVolume(double volume) {
    _volume = volume;
    volumeChanges.add(volume);
  }

  @override
  void setPitch(double pitch) {
    _pitch = pitch;
    pitchChanges.add(pitch);
  }
}

Future<FakeTtsPanelController> _pumpPanel(
  WidgetTester tester,
  TtsPlaybackState initialState,
) async {
  final controller = FakeTtsPanelController(initialState);
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        ttsPanelControllerProvider.overrideWithValue(controller),
      ],
      child: TtsWidget(epubPlayerKey: GlobalKey<EpubPlayerState>()),
    ),
  );
  // TtsSessionGate finishes its initialize future in a microtask, so one more
  // frame is needed before the playback tri-state is visible.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ttsService': 'system',
      'ttsRate': 0.6,
      'ttsVolume': 1.0,
      'ttsPitch': 1.0,
    });
    await Prefs().initPrefs();
  });

  group('loading tri-state', () {
    for (final phase in <TtsPlaybackPhase>[
      TtsPlaybackPhase.initializing,
      TtsPlaybackPhase.loadingText,
      TtsPlaybackPhase.buffering,
      TtsPlaybackPhase.resuming,
      TtsPlaybackPhase.pausing,
      TtsPlaybackPhase.stopping,
      TtsPlaybackPhase.switchingEngine,
    ]) {
      testWidgets(
          '${phase.name} keeps the transport panel instead of a loading card',
          (tester) async {
        await _pumpPanel(tester, _state(phase: phase));

        // Regression: a loading skeleton/card collapsed the popup into a
        // narrow white block. The panel content now stays mounted and a slim
        // progress bar communicates loading instead.
        expect(find.byType(AppSkeleton), findsNothing);
        expect(find.byType(Card), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(AppEmptyState), findsNothing);
        expect(find.byType(AppErrorState), findsNothing);
        expect(find.byIcon(EvaIcons.stop_circle_outline), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('error tri-state', () {
    testWidgets('error renders AppErrorState and retry preserves cursor',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(
          phase: TtsPlaybackPhase.error,
          sessionId: 7,
          cursor: _cursor,
          error: const TtsSynthesisError(
            engine: TtsEngineKind.system,
            message: 'network down',
          ),
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.byType(AppSkeleton), findsNothing);
      // Retry label comes from the existing localisations.
      expect(find.text('Retry'), findsOneWidget);
      // The engine failure text is diagnostics, never rendered verbatim.
      expect(find.textContaining('network down'), findsNothing);

      final cursorBefore = controller.state.cursor;
      final sessionBefore = controller.state.sessionId;

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(controller.retryCount, 1);
      // Retry must be "continue from here": no stop/restart, no replay.
      expect(controller.stopCount, 0);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.state.cursor, cursorBefore);
      expect(controller.state.sessionId, sessionBefore);
      expect(controller.state.cursor!.charOffset, 7);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retry from a state that moved on keeps the session cursor',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(
          phase: TtsPlaybackPhase.error,
          sessionId: 3,
          cursor: _cursor,
          error: const TtsAudioOutputError(
            engine: TtsEngineKind.system,
            message: 'audio device lost',
          ),
        ),
      );

      // The retry intent itself does not mutate the controller state: the
      // handler owns the transition and keeps the cursor while reloading.
      final before = controller.state;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(controller.retryCount, 1);
      expect(controller.state, before);
      expect(controller.state.sessionId, 3);
    });
  });

  group('empty tri-state', () {
    testWidgets('empty renders AppEmptyState with retry action',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(
          phase: TtsPlaybackPhase.empty,
          sessionId: 2,
          cursor: _cursor,
          error: const TtsEmptyTextError(engine: TtsEngineKind.system),
        ),
      );

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppSkeleton), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(controller.retryCount, 1);
      expect(controller.stopCount, 0);
      expect(controller.playCount, 0);
      expect(controller.state.cursor, _cursor);
      expect(tester.takeException(), isNull);
    });
  });

  group('playing controls', () {
    testWidgets('playing renders playback, navigation and setting controls',
        (tester) async {
      await _pumpPanel(
        tester,
        _state(phase: TtsPlaybackPhase.playing, cursor: _cursor),
      );

      expect(find.byType(AppSkeleton), findsNothing);
      expect(find.byIcon(EvaIcons.pause_circle_outline), findsOneWidget);
      expect(find.byIcon(EvaIcons.stop_circle_outline), findsOneWidget);
      expect(find.byIcon(EvaIcons.chevron_left), findsOneWidget);
      expect(find.byIcon(EvaIcons.chevron_right), findsOneWidget);
      expect(find.byIcon(EvaIcons.arrowhead_left), findsOneWidget);
      expect(find.byIcon(EvaIcons.arrowhead_right), findsOneWidget);
      // Sleep timer + volume + pitch + rate sliders.
      expect(find.byType(Slider), findsNWidgets(4));
      expect(find.byKey(const Key('tts-rate-slider')), findsOneWidget);
      expect(find.text('Narrator'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Pitch'), findsOneWidget);
      expect(find.text('Rate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paused renders the play control instead of pause',
        (tester) async {
      await _pumpPanel(
        tester,
        _state(phase: TtsPlaybackPhase.paused, cursor: _cursor),
      );

      expect(find.byIcon(EvaIcons.play_circle_outline), findsOneWidget);
      expect(find.byIcon(EvaIcons.pause_circle_outline), findsNothing);
      expect(find.byIcon(EvaIcons.stop_circle_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('playing controls follow playback state updates',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(phase: TtsPlaybackPhase.initializing),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(AppSkeleton), findsNothing);

      controller.emit(_state(phase: TtsPlaybackPhase.playing, cursor: _cursor));
      await tester.pump();
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(AppSkeleton), findsNothing);
      expect(find.byIcon(EvaIcons.pause_circle_outline), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });

  group('rate changes', () {
    testWidgets('rate slider calls changeRate only (never play/pause/stop)',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(
          phase: TtsPlaybackPhase.playing,
          rate: 0.6,
          cursor: _cursor,
        ),
      );

      final rateSlider = tester.widget<Slider>(
        find.byKey(const Key('tts-rate-slider')),
      );
      expect(rateSlider.value, closeTo(0.6, 1e-9));

      rateSlider.onChanged!(1.4);
      await tester.pump();

      expect(controller.rateChanges, <double>[1.4]);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(controller.retryCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('volume and pitch sliders delegate to the controller',
        (tester) async {
      final controller = await _pumpPanel(
        tester,
        _state(phase: TtsPlaybackPhase.playing, cursor: _cursor),
      );

      final volumeSlider = tester.widget<Slider>(
        find.byKey(const Key('tts-volume-slider')),
      );
      volumeSlider.onChanged!(0.4);
      await tester.pump();
      final pitchSlider = tester.widget<Slider>(
        find.byKey(const Key('tts-pitch-slider')),
      );
      pitchSlider.onChanged!(1.5);
      await tester.pump();

      expect(controller.volumeChanges, <double>[0.4]);
      expect(controller.pitchChanges, <double>[1.5]);
      // Slider tweaks never restart playback.
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
