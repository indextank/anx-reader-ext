import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/design_system_test_utils.dart';

const Size _wideStage = Size(1000, 800);
const Size _narrowStage = Size(320, 640);

final Finder _toggle = find.byKey(const Key('tts-fab-toggle'));
final Finder _dragArea = find.byKey(const Key('tts-fab-drag'));
final Finder _expandedCard = find.byKey(const Key('tts-fab-expanded'));
final Finder _playButton = find.byKey(const Key('tts-fab-play'));
final Finder _stopButton = find.byKey(const Key('tts-fab-stop'));
final Finder _rateMenu = find.byKey(const Key('tts-rate-menu'));
final Finder _engineMenu = find.byKey(const Key('tts-engine-menu'));
final Finder _errorRetry = find.byKey(const Key('tts-fab-error-retry'));

/// In-memory controller: the widget is exercised without ever touching
/// [TtsHandler], the audio plugins or the preference-backed production wiring.
class _FakeTtsFabController implements TtsFabController {
  _FakeTtsFabController({
    TtsPlaybackPhase phase = TtsPlaybackPhase.playing,
    TtsEngineKind engine = TtsEngineKind.system,
    String serviceId = 'system',
    double rate = 1.0,
  })  : _serviceId = serviceId,
        _rate = rate,
        _playbackState = ValueNotifier<TtsPlaybackState>(
          TtsPlaybackState(
            phase: phase,
            engine: engine,
            sessionId: 1,
            rate: rate,
          ),
        );

  final ValueNotifier<TtsPlaybackState> _playbackState;
  String _serviceId;
  double _rate;

  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int retryCount = 0;

  final List<String> switchEngineCalls = <String>[];
  bool failNextSwitch = false;

  @override
  ValueListenable<TtsPlaybackState> get playbackState => _playbackState;

  @override
  double get rate => _rate;

  @override
  String get serviceId => _serviceId;

  void emitPhase(TtsPlaybackPhase phase, {TtsPlaybackError? error}) {
    _playbackState.value = _playbackState.value.copyWith(
      phase: phase,
      error: error,
      clearError: error == null,
    );
  }

  @override
  Future<void> play() async {
    playCount++;
    emitPhase(TtsPlaybackPhase.playing);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPhase(TtsPlaybackPhase.paused);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    emitPhase(TtsPlaybackPhase.stopped);
  }

  @override
  Future<void> retry() async {
    retryCount++;
    emitPhase(TtsPlaybackPhase.playing);
  }

  @override
  Future<void> switchEngine(String serviceId) async {
    switchEngineCalls.add(serviceId);
    if (failNextSwitch) {
      failNextSwitch = false;
      emitPhase(
        TtsPlaybackPhase.error,
        error: TtsEngineSwitchError(
          engine: TtsEngineKind.system,
          message: 'engine unavailable in fake',
        ),
      );
      return;
    }
    _serviceId = serviceId;
    emitPhase(TtsPlaybackPhase.switchingEngine);
  }

  @override
  void setRate(double value) {
    _rate = value;
    Prefs().ttsRate = value;
    _playbackState.value = _playbackState.value.copyWith(rate: value);
  }
}

Future<_FakeTtsFabController> _pumpFab(
  WidgetTester tester, {
  TtsPlaybackPhase phase = TtsPlaybackPhase.playing,
  String serviceId = 'system',
  double rate = 1.0,
  Size stage = _wideStage,
  TextScaler? textScaler,
  bool eInkMode = false,
  TextDirection? textDirection,
  bool disableAnimations = false,
  Key? fabKey,
}) async {
  tester.view.physicalSize = stage;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = _FakeTtsFabController(
    phase: phase,
    serviceId: serviceId,
    rate: rate,
  );

  // The engine selector watches `enabledTtsEnginesProvider`; this harness has
  // no production container, so provide every engine to keep the pre-filter
  // expectations (6 listed engines) intact.
  Widget child = ProviderScope(
    overrides: [
      enabledTtsEnginesProvider.overrideWith(
        (ref) => TtsService.values.toList(growable: false),
      ),
    ],
    child: SizedBox.expand(
      child: TtsFab(key: fabKey, controller: controller),
    ),
  );
  if (textDirection != null) {
    child = Directionality(textDirection: textDirection, child: child);
  }
  if (disableAnimations) {
    final inner = child;
    child = Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: inner,
      ),
    );
  }
  await pumpDesignSystem(
    tester,
    child,
    textScaler: textScaler,
    eInkMode: eInkMode,
  );
  // Preparing phases render an indeterminate progress indicator, which never
  // settles; pump a bounded number of frames instead of pumpAndSettle.
  if (phase == TtsPlaybackPhase.buffering ||
      phase == TtsPlaybackPhase.initializing ||
      phase == TtsPlaybackPhase.loadingText) {
    await _pumpFrames(tester);
  } else {
    await tester.pumpAndSettle();
  }
  return controller;
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(_toggle);
  await tester.pumpAndSettle();
}

/// Pumps a bounded number of frames instead of settling: indeterminate
/// progress indicators (the "switching engine" spinner) animate forever and
/// would make `pumpAndSettle` time out.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openRateMenu(WidgetTester tester) async {
  await tester.tap(_rateMenu);
  await tester.pumpAndSettle();
}

Future<void> _openEngineMenu(WidgetTester tester) async {
  await tester.tap(_engineMenu);
  await tester.pumpAndSettle();
}

/// The widget's own fade/ignore-pointer wrapper. The Material FAB internals
/// contribute additional IgnorePointers, so the root one is selected from the
/// outermost descendants of [TtsFab].
IgnorePointer _rootIgnorePointer(WidgetTester tester) {
  final finder = find
      .descendant(of: find.byType(TtsFab), matching: find.byType(IgnorePointer))
      .first;
  return tester.widget<IgnorePointer>(finder);
}

AnimatedOpacity _rootOpacity(WidgetTester tester) {
  final finder = find
      .descendant(
        of: find.byType(TtsFab),
        matching: find.byType(AnimatedOpacity),
      )
      .first;
  return tester.widget<AnimatedOpacity>(finder);
}

void _expectVisible(WidgetTester tester) {
  expect(_rootIgnorePointer(tester).ignoring, isFalse);
  expect(_rootOpacity(tester).opacity, 1.0);
}

void _expectHidden(WidgetTester tester) {
  expect(_rootIgnorePointer(tester).ignoring, isTrue);
  expect(_rootOpacity(tester).opacity, 0.0);
}

/// The player has to stay inside the screen even after drags/resizes.
void _expectInsideScreen(WidgetTester tester, Size screen) {
  final rect = tester.getRect(_toggle);
  expect(rect.left, greaterThanOrEqualTo(-0.5));
  expect(rect.top, greaterThanOrEqualTo(-0.5));
  expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
  expect(rect.bottom, lessThanOrEqualTo(screen.height + 0.5));
}

double _prefX() => Prefs().ttsFabAnchorX;
double _prefY() => Prefs().ttsFabAnchorY;

bool _isInsideElement(Element candidate, Element ancestor) {
  if (candidate == ancestor) return true;
  var found = false;
  candidate.visitAncestorElements((parent) {
    if (parent == ancestor) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Moves keyboard focus onto a transport control inside the expanded pill so
/// the card's key-event handler (ContextMenu / Shift+F10) is reachable.
Future<void> _focusInsideExpandedCard(WidgetTester tester) async {
  final card = tester.element(_expandedCard);
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext is Element && _isInsideElement(focusContext, card)) {
      return;
    }
  }
  fail('keyboard focus never reached a control inside the expanded player');
}

/// Key of an engine menu item. The item key lives on the outer KeyedSubtree,
/// so exactly one node matches (no `RadioMenuButton` key forwarding).
Finder _engineItem(TtsService service) =>
    find.byKey(Key('tts-engine-item-${service.name}'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ttsService': 'system',
      'ttsRate': 1.0,
      'ttsVolume': 1.0,
      'ttsPitch': 1.0,
      'ttsFabAnchorX': 1.0,
      'ttsFabAnchorY': 1.0,
    });
    await Prefs().initPrefs();
  });

  group('visibility from the typed playback state', () {
    const visiblePhases = <TtsPlaybackPhase>[
      TtsPlaybackPhase.initializing,
      TtsPlaybackPhase.loadingText,
      TtsPlaybackPhase.buffering,
      TtsPlaybackPhase.playing,
      TtsPlaybackPhase.pausing,
      TtsPlaybackPhase.paused,
      TtsPlaybackPhase.resuming,
      TtsPlaybackPhase.switchingEngine,
    ];
    for (final phase in visiblePhases) {
      testWidgets('visible during ${phase.name}', (tester) async {
        await _pumpFab(tester, phase: phase);
        _expectVisible(tester);
      });
    }

    const hiddenPhases = <TtsPlaybackPhase>[
      TtsPlaybackPhase.idle,
      TtsPlaybackPhase.stopped,
      TtsPlaybackPhase.stopping,
      TtsPlaybackPhase.empty,
    ];
    for (final phase in hiddenPhases) {
      testWidgets('hidden during ${phase.name}', (tester) async {
        await _pumpFab(tester, phase: phase);
        _expectHidden(tester);

        // A hidden player must not react to taps even though it stays mounted
        // so a new session can reveal it again.
        await tester.tap(_toggle, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(_expandedCard, findsNothing);
      });
    }

    testWidgets('a stale error on first mount stays hidden', (tester) async {
      // No active playback happened during this mount, so an error carried
      // over from an earlier session must not pop the retry player.
      await _pumpFab(
        tester,
        phase: TtsPlaybackPhase.error,
      );
      _expectHidden(tester);

      await tester.tap(_toggle, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_expandedCard, findsNothing);
      expect(_errorRetry, findsNothing);
    });

    testWidgets('becomes visible when a new session starts', (tester) async {
      final controller =
          await _pumpFab(tester, phase: TtsPlaybackPhase.stopped);
      _expectHidden(tester);

      controller.emitPhase(TtsPlaybackPhase.playing);
      await tester.pumpAndSettle();
      _expectVisible(tester);

      await _expand(tester);
      expect(_expandedCard, findsOneWidget);
    });

    testWidgets('an error after active playback stays visible with retry',
        (tester) async {
      final controller = await _pumpFab(tester);
      controller.emitPhase(
        TtsPlaybackPhase.error,
        error: TtsEngineSwitchError(
          engine: TtsEngineKind.system,
          message: 'boom',
        ),
      );
      await tester.pumpAndSettle();
      _expectVisible(tester);

      await _expand(tester);
      expect(_errorRetry, findsOneWidget);
      expect(_playButton, findsNothing);
    });
  });

  group('expand and collapse', () {
    testWidgets('starts collapsed and expands into the control pill',
        (tester) async {
      await _pumpFab(tester);

      expect(_expandedCard, findsNothing);
      expect(_engineMenu, findsNothing);
      expect(_rateMenu, findsNothing);
      expect(_playButton, findsNothing);
      expect(_stopButton, findsNothing);

      await _expand(tester);

      expect(_expandedCard, findsOneWidget);
      expect(_engineMenu, findsOneWidget);
      expect(_rateMenu, findsOneWidget);
      expect(_playButton, findsOneWidget);
      expect(_stopButton, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggling again collapses the pill', (tester) async {
      await _pumpFab(tester);
      await _expand(tester);
      expect(_expandedCard, findsOneWidget);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();

      expect(_expandedCard, findsNothing);
      expect(_engineMenu, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stop delegates then collapses and fades out', (tester) async {
      final controller = await _pumpFab(tester);
      await _expand(tester);

      await tester.tap(_stopButton);
      await tester.pumpAndSettle();

      expect(controller.stopCount, 1);
      expect(_expandedCard, findsNothing);
      _expectHidden(tester);
    });

    testWidgets('play/pause delegates through the same transport button',
        (tester) async {
      final controller = await _pumpFab(tester);
      await _expand(tester);

      await tester.tap(_playButton);
      await tester.pumpAndSettle();
      expect(controller.pauseCount, 1);
      expect(controller.playbackState.value.phase, TtsPlaybackPhase.paused);

      await tester.tap(_playButton);
      await tester.pumpAndSettle();
      expect(controller.playCount, 1);
      expect(controller.playbackState.value.phase, TtsPlaybackPhase.playing);
      expect(controller.stopCount, 0);
    });

    testWidgets('buffering counts as playing intent for the transport button',
        (tester) async {
      final controller =
          await _pumpFab(tester, phase: TtsPlaybackPhase.buffering);
      await tester.tap(_toggle);
      await _pumpFrames(tester);

      // The button offers pause (same convention as the collapsed FAB)...
      expect(
        find.descendant(
          of: _playButton,
          matching: find.byIcon(EvaIcons.pause_circle_outline),
        ),
        findsOneWidget,
      );
      // ...and tapping it pauses instead of starting another session.
      await tester.tap(_playButton);
      await tester.pumpAndSettle();
      expect(controller.pauseCount, 1);
      expect(controller.playCount, 0);
    });

    testWidgets(
        'preparing shows progress instead of pretending to play while silent',
        (tester) async {
      final controller =
          await _pumpFab(tester, phase: TtsPlaybackPhase.buffering);

      // Collapsed: the FAB shows progress while nothing is audible yet.
      expect(
        find.byKey(const ValueKey<String>('tts-fab-preparing')),
        findsOneWidget,
      );

      await tester.tap(_toggle);
      await _pumpFrames(tester);

      // Expanded: the FAB is the close toggle; the grip carries the progress
      // indicator so a long synthesis wait never looks like a frozen player.
      expect(
        find.byKey(const ValueKey<String>('tts-fab-preparing')),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Audio becomes audible: the indicator is replaced by the normal grip.
      controller.emitPhase(TtsPlaybackPhase.playing);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('pausing shows the play affordance and delegates to play',
        (tester) async {
      final controller =
          await _pumpFab(tester, phase: TtsPlaybackPhase.pausing);
      await _expand(tester);

      expect(
        find.descendant(
          of: _playButton,
          matching: find.byIcon(EvaIcons.play_circle_outline),
        ),
        findsOneWidget,
      );
      await tester.tap(_playButton);
      await tester.pumpAndSettle();
      expect(controller.playCount, 1);
      expect(controller.pauseCount, 0);
    });

    testWidgets('resuming is treated as playing intent by the transport button',
        (tester) async {
      // Resuming is a transient phase: only the affordance is asserted, the
      // state machine is allowed to ignore the pause request.
      await _pumpFab(tester, phase: TtsPlaybackPhase.resuming);
      await _expand(tester);
      expect(
        find.descendant(
          of: _playButton,
          matching: find.byIcon(EvaIcons.pause_circle_outline),
        ),
        findsOneWidget,
      );
    });
  });

  group('rate menu', () {
    testWidgets('lists the six supported rates with the current selection',
        (tester) async {
      await _pumpFab(tester, rate: 1.0);
      await _expand(tester);
      await _openRateMenu(tester);

      final options = tester
          .widgetList<RadioMenuButton<double>>(
            find.byType(RadioMenuButton<double>),
          )
          .toList();
      expect(options, hasLength(TtsFab.supportedRates.length));
      for (final rate in TtsFab.supportedRates) {
        expect(find.text('${rate.toStringAsFixed(1)}×'), findsWidgets);
      }
      final selected =
          options.where((item) => item.groupValue == item.value).toList();
      expect(selected, hasLength(1));
      expect(selected.single.value, 1.0);
    });

    testWidgets('selecting a rate updates Prefs and keeps playing',
        (tester) async {
      final controller = await _pumpFab(tester, rate: 1.0);
      await _expand(tester);
      await _openRateMenu(tester);

      await tester.tap(
        find.widgetWithText(RadioMenuButton<double>, '1.8×'),
      );
      await tester.pumpAndSettle();

      expect(Prefs().ttsRate, 1.8);
      expect(find.byType(RadioMenuButton<double>), findsNothing);
      expect(find.text('1.8×'), findsOneWidget);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(
        controller.playbackState.value.phase,
        TtsPlaybackPhase.playing,
      );
    });

    testWidgets('selecting a rate while paused keeps the paused state',
        (tester) async {
      final controller =
          await _pumpFab(tester, phase: TtsPlaybackPhase.paused, rate: 1.0);
      await _expand(tester);
      await _openRateMenu(tester);

      await tester.tap(
        find.widgetWithText(RadioMenuButton<double>, '0.6×'),
      );
      await tester.pumpAndSettle();

      expect(Prefs().ttsRate, 0.6);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(controller.playbackState.value.phase, TtsPlaybackPhase.paused);
    });
  });

  group('engine menu', () {
    testWidgets('lists every engine with the current one selected',
        (tester) async {
      final controller = await _pumpFab(tester, serviceId: 'system');
      await _expand(tester);
      await _openEngineMenu(tester);

      final context = tester.element(_engineMenu);
      for (final service in TtsService.values) {
        final item = _engineItem(service);
        expect(item, findsOneWidget);
        expect(
          find.descendant(
            of: item,
            matching: find.text(service.getLabel(context)),
          ),
          findsOneWidget,
        );
      }

      final options = tester
          .widgetList<RadioMenuButton<String>>(
            find.byType(RadioMenuButton<String>),
          )
          .toList();
      expect(options, hasLength(6));
      final selected =
          options.where((item) => item.groupValue == item.value).toList();
      expect(selected, hasLength(1));
      expect(selected.single.value, controller.serviceId);
    });

    testWidgets('selecting another engine only calls switchEngine',
        (tester) async {
      final controller = await _pumpFab(tester, serviceId: 'system');
      await _expand(tester);
      await _openEngineMenu(tester);

      await tester.tap(_engineItem(TtsService.aliyun));
      await _pumpFrames(tester);

      expect(controller.switchEngineCalls, <String>['aliyun']);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(
        controller.playbackState.value.phase,
        TtsPlaybackPhase.switchingEngine,
      );
      expect(_engineItem(TtsService.aliyun), findsNothing);

      // The selector reflects the engine being switched to.
      final context = tester.element(_engineMenu);
      expect(find.text(TtsService.aliyun.getLabel(context)), findsOneWidget);

      // Completing the switch re-enables the selector.
      controller.emitPhase(TtsPlaybackPhase.playing);
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(_engineMenu);
      expect(button.onPressed, isNotNull);
      expect(
        find.descendant(
          of: _engineMenu,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });

    testWidgets('the selector is disabled and shows progress while switching',
        (tester) async {
      final controller = await _pumpFab(tester);
      await _expand(tester);

      controller.emitPhase(TtsPlaybackPhase.switchingEngine);
      await _pumpFrames(tester);

      expect(
        find.descendant(
          of: _engineMenu,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final button = tester.widget<TextButton>(_engineMenu);
      expect(button.onPressed, isNull);

      await tester.tap(_engineMenu, warnIfMissed: false);
      await _pumpFrames(tester);
      expect(find.byType(RadioMenuButton<String>), findsNothing);
    });

    testWidgets('a failed switch surfaces feedback and an error retry',
        (tester) async {
      final controller = await _pumpFab(tester, serviceId: 'system');
      await _expand(tester);
      await _openEngineMenu(tester);

      controller.failNextSwitch = true;
      await tester.tap(_engineItem(TtsService.aliyun));
      await tester.pumpAndSettle();

      expect(controller.switchEngineCalls, <String>['aliyun']);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
      expect(controller.stopCount, 0);
      expect(controller.playbackState.value.phase, TtsPlaybackPhase.error);
      expect(
        controller.playbackState.value.error,
        isA<TtsEngineSwitchError>(),
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_errorRetry, findsOneWidget);

      // Drain the snackbar timer before the test ends.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the retry affordance calls controller.retry', (tester) async {
      final controller = await _pumpFab(tester);
      await _expand(tester);
      controller.emitPhase(
        TtsPlaybackPhase.error,
        error: TtsEngineSwitchError(
          engine: TtsEngineKind.system,
          message: 'boom',
        ),
      );
      await tester.pumpAndSettle();
      expect(_errorRetry, findsOneWidget);

      await tester.tap(_errorRetry);
      await tester.pumpAndSettle();

      expect(controller.retryCount, 1);
      expect(
        controller.playbackState.value.phase,
        TtsPlaybackPhase.playing,
      );
      expect(_errorRetry, findsNothing);
      expect(_playButton, findsOneWidget);
    });
  });

  group('drag and position persistence', () {
    testWidgets('defaults to the bottom-right corner of the reader stage',
        (tester) async {
      await _pumpFab(tester);

      final rect = tester.getRect(_toggle);
      expect(rect.width, inInclusiveRange(40.0, 56.0));
      expect(rect.height, inInclusiveRange(40.0, 56.0));
      expect(rect.right, greaterThan(_wideStage.width - 48));
      expect(rect.bottom, greaterThan(_wideStage.height - 48));
      expect(_prefX(), 1.0);
      expect(_prefY(), 1.0);
    });

    testWidgets('dragging moves the player and persists a normalized anchor',
        (tester) async {
      final controller = await _pumpFab(tester);
      final before = tester.getRect(_toggle);

      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();

      final after = tester.getRect(_toggle);
      expect(after.left, lessThan(before.left - 200));
      expect(after.top, lessThan(before.top - 100));
      expect(_prefX(), inInclusiveRange(0.0, 1.0));
      expect(_prefY(), inInclusiveRange(0.0, 1.0));
      expect(_prefX(), lessThan(1.0));
      expect(_prefY(), lessThan(1.0));
      _expectInsideScreen(tester, _wideStage);
      expect(
        controller.playCount + controller.pauseCount + controller.stopCount,
        0,
      );
    });

    testWidgets('dragging past the edges clamps the player inside the stage',
        (tester) async {
      await _pumpFab(tester);

      await tester.drag(_dragArea, const Offset(-4000, -4000));
      await tester.pumpAndSettle();
      var rect = tester.getRect(_toggle);
      expect(rect.left, lessThan(48));
      expect(rect.top, lessThan(48));
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.top, greaterThanOrEqualTo(-0.5));
      expect(_prefX(), closeTo(0, 1e-6));
      expect(_prefY(), closeTo(0, 1e-6));

      await tester.drag(_dragArea, const Offset(4000, 4000));
      await tester.pumpAndSettle();
      rect = tester.getRect(_toggle);
      expect(rect.right, greaterThan(_wideStage.width - 48));
      expect(rect.bottom, greaterThan(_wideStage.height - 48));
      _expectInsideScreen(tester, _wideStage);
      expect(_prefX(), closeTo(1, 1e-6));
      expect(_prefY(), closeTo(1, 1e-6));
    });

    testWidgets('the expanded pill is draggable too', (tester) async {
      await _pumpFab(tester);
      await _expand(tester);

      await tester.drag(_dragArea, const Offset(-250, -150));
      await tester.pumpAndSettle();

      expect(_prefX(), lessThan(1.0));
      expect(_prefY(), lessThan(1.0));
      final cardRect = tester.getRect(_expandedCard);
      expect(cardRect.left, greaterThanOrEqualTo(-0.5));
      expect(cardRect.top, greaterThanOrEqualTo(-0.5));
      _expectInsideScreen(tester, _wideStage);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shrinking the window re-clamps the player into view',
        (tester) async {
      await _pumpFab(tester, stage: _wideStage);
      await tester.drag(_dragArea, const Offset(-400, -300));
      await tester.pumpAndSettle();
      final anchorX = _prefX();
      final anchorY = _prefY();

      tester.view.physicalSize = _narrowStage;
      await tester.pumpAndSettle();

      _expectInsideScreen(tester, _narrowStage);
      // Resizing must not rewrite the stored fractions.
      expect(_prefX(), anchorX);
      expect(_prefY(), anchorY);
      expect(tester.takeException(), isNull);
    });

    testWidgets('restores the persisted anchor after a remount',
        (tester) async {
      await _pumpFab(tester, fabKey: const ValueKey('fab-first'));
      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();
      final before = tester.getRect(_toggle);
      final anchorX = _prefX();
      final anchorY = _prefY();

      await _pumpFab(tester, fabKey: const ValueKey('fab-second'));

      final after = tester.getRect(_toggle);
      expect(after.left, closeTo(before.left, 1));
      expect(after.top, closeTo(before.top, 1));
      expect(_prefX(), anchorX);
      expect(_prefY(), anchorY);
    });

    testWidgets('long press offers and applies "reset to default position"',
        (tester) async {
      await _pumpFab(tester);
      await _expand(tester);
      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();
      expect(_prefX(), lessThan(1.0));

      final cardRect = tester.getRect(_expandedCard);
      await tester.longPressAt(
        cardRect.topLeft + Offset(12, cardRect.height / 2),
      );
      await tester.pumpAndSettle();

      final resetItem =
          find.byWidgetPredicate((widget) => widget is PopupMenuItem);
      expect(resetItem, findsOneWidget);

      await tester.tap(resetItem);
      await tester.pumpAndSettle();

      expect(_prefX(), closeTo(1, 1e-6));
      expect(_prefY(), closeTo(1, 1e-6));
      final fabRect = tester.getRect(_toggle);
      expect(fabRect.right, greaterThan(_wideStage.width - 48));
      expect(fabRect.bottom, greaterThan(_wideStage.height - 48));

      // Drain the confirmation toast timer before the test ends.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('right click offers the same reset menu', (tester) async {
      await _pumpFab(tester);
      await _expand(tester);
      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();

      final cardRect = tester.getRect(_expandedCard);
      await tester.tapAt(
        cardRect.topLeft + Offset(12, cardRect.height / 2),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      final resetItem =
          find.byWidgetPredicate((widget) => widget is PopupMenuItem);
      expect(resetItem, findsOneWidget);

      await tester.tap(resetItem);
      await tester.pumpAndSettle();

      expect(_prefX(), closeTo(1, 1e-6));
      expect(_prefY(), closeTo(1, 1e-6));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('context menu key offers reset for keyboard users',
        (tester) async {
      await _pumpFab(tester);
      await _expand(tester);
      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();
      expect(_prefX(), lessThan(1.0));

      await _focusInsideExpandedCard(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      final resetItem =
          find.byWidgetPredicate((widget) => widget is PopupMenuItem);
      expect(resetItem, findsOneWidget);

      await tester.tap(resetItem);
      await tester.pumpAndSettle();
      expect(_prefX(), closeTo(1, 1e-6));
      expect(_prefY(), closeTo(1, 1e-6));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('shift+F10 offers reset for keyboard users', (tester) async {
      await _pumpFab(tester);
      await _expand(tester);
      await tester.drag(_dragArea, const Offset(-300, -200));
      await tester.pumpAndSettle();
      expect(_prefX(), lessThan(1.0));

      await _focusInsideExpandedCard(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      final resetItem =
          find.byWidgetPredicate((widget) => widget is PopupMenuItem);
      expect(resetItem, findsOneWidget);

      await tester.tap(resetItem);
      await tester.pumpAndSettle();
      expect(_prefX(), closeTo(1, 1e-6));
      expect(_prefY(), closeTo(1, 1e-6));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('responsive layout', () {
    testWidgets('wide stage keeps the pill on a single row without overflow',
        (tester) async {
      await _pumpFab(tester, stage: _wideStage);
      await _expand(tester);

      expect(tester.takeException(), isNull);
      expect(_expandedCard, findsOneWidget);

      final engineCenter = tester.getCenter(_engineMenu);
      final stopCenter = tester.getCenter(_stopButton);
      expect((engineCenter.dy - stopCenter.dy).abs(), lessThan(6));

      final cardSize = tester.getSize(_expandedCard);
      expect(cardSize.height, lessThan(96));

      final cardRect = tester.getRect(_expandedCard);
      final fabRect = tester.getRect(_toggle);
      expect(cardRect.right, lessThanOrEqualTo(fabRect.left + 0.5));
    });

    testWidgets('narrow stage with large text uses two rows without overflow',
        (tester) async {
      await _pumpFab(
        tester,
        stage: _wideStage,
        fabKey: const ValueKey('fab-wide'),
      );
      await _expand(tester);
      final wideCardHeight = tester.getSize(_expandedCard).height;

      await _pumpFab(
        tester,
        stage: _narrowStage,
        textScaler: const TextScaler.linear(1.3),
        fabKey: const ValueKey('fab-narrow'),
      );
      await _expand(tester);

      expect(tester.takeException(), isNull);
      final cardSize = tester.getSize(_expandedCard);
      expect(cardSize.height, greaterThan(wideCardHeight));
      expect(cardSize.width, lessThanOrEqualTo(_narrowStage.width));

      // The engine selector moves to its own row above the transport row.
      final engineCenter = tester.getCenter(_engineMenu);
      final playCenter = tester.getCenter(_playButton);
      expect((engineCenter.dy - playCenter.dy).abs(), greaterThan(8));

      for (final finder in <Finder>[
        _engineMenu,
        _playButton,
        _rateMenu,
        _stopButton,
      ]) {
        expect(finder, findsOneWidget);
        expect(finder.hitTestable(), findsOneWidget);
      }
      _expectInsideScreen(tester, _narrowStage);
    });

    testWidgets('RTL layout does not overflow', (tester) async {
      await _pumpFab(
        tester,
        stage: _narrowStage,
        textScaler: const TextScaler.linear(1.3),
        textDirection: TextDirection.rtl,
      );
      await _expand(tester);

      expect(tester.takeException(), isNull);
      expect(_expandedCard, findsOneWidget);
      for (final finder in <Finder>[
        _engineMenu,
        _playButton,
        _rateMenu,
        _stopButton,
      ]) {
        expect(finder, findsOneWidget);
      }
      _expectInsideScreen(tester, _narrowStage);
    });

    testWidgets('e-ink mode renders without exceptions', (tester) async {
      await _pumpFab(tester, eInkMode: true);
      // e-ink drops the elevation/shadow in favour of an outline treatment.
      expect(tester.widget<FloatingActionButton>(_toggle).elevation, 0);

      await _expand(tester);

      expect(tester.takeException(), isNull);
      expect(_expandedCard, findsOneWidget);
      expect(_engineMenu.hitTestable(), findsOneWidget);
    });

    testWidgets('reduce motion renders and toggles without exceptions',
        (tester) async {
      await _pumpFab(tester, disableAnimations: true);
      await _expand(tester);

      expect(tester.takeException(), isNull);
      expect(_expandedCard, findsOneWidget);

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_expandedCard, findsNothing);
    });
  });
}
