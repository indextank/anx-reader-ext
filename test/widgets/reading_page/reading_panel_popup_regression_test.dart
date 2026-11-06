import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/reading_chrome.dart';
import 'package:anx_reader/widgets/reading_page/reading_panel_coordinator.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/design_system_test_utils.dart';

/// 深色阅读主题：应用主题仍为浅色，旧实现会在弹层里露出应用浅色背景
/// （近白色块）。弹层必须采用阅读主题的深色表面与浅色文字。
const _darkReadThemeJson =
    '{"id":7,"backgroundColor":"FF121212","textColor":"FFCCCCCC","backgroundImagePath":""}';
const _darkReadingSurface = Color(0xFF121212);
const _darkReadingText = Color(0xFFCCCCCC);

/// 应用浅色主题的表面色（旧弹层错误复用了这个颜色）。
const _appLightSurface = Color(0xFFF2F2F7);

const _themeSubpageKey = ValueKey('popup-regression-subpage');
const _allowedPanelBackgroundLuminance = 0.2;

class _PanelHarness extends StatefulWidget {
  const _PanelHarness({
    super.key,
    required this.styleThemesLoader,
    required this.ttsBuilder,
  });

  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final WidgetBuilder ttsBuilder;

  @override
  State<_PanelHarness> createState() => _PanelHarnessState();
}

class _PanelHarnessState extends State<_PanelHarness> {
  final coordinatorKey = GlobalKey<ReadingPanelCoordinatorState>();
  final chromeKey = GlobalKey<ReadingChromeState>();
  final readerFocusNode = FocusNode(debugLabel: 'popup-regression-reader');
  var aiPosition = AiPanelPositionEnum.right;
  var notesPosition = AiPanelPositionEnum.popup;
  var stylePosition = AiPanelPositionEnum.popup;

  @override
  void dispose() {
    readerFocusNode.dispose();
    super.dispose();
  }

  void setStylePosition(AiPanelPositionEnum value) {
    setState(() => stylePosition = value);
  }

  @override
  Widget build(BuildContext context) {
    return ReadingPanelCoordinator(
      key: coordinatorKey,
      chromeKey: chromeKey,
      reader: Focus(
        focusNode: readerFocusNode,
        child: const Text('reader-content'),
      ),
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
        ],
      ),
      onShow: readerFocusNode.unfocus,
      onHide: readerFocusNode.requestFocus,
      aiBuilder: (_) => const Text('ai-panel'),
      notesBuilder: (_) => const Text('notes-panel'),
      ttsBuilder: widget.ttsBuilder,
      styleThemesLoader: widget.styleThemesLoader,
      styleBuilder: (context, themes, setCurrentPage) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('style-root'),
          AppButton(
            label: 'open-style-subpage',
            onPressed: () => setCurrentPage(
              const Text('style-subpage', key: _themeSubpageKey),
            ),
          ),
        ],
      ),
      ttsFab: const SizedBox(key: ValueKey('tts-fab-placeholder')),
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
      onSwitchPosition: (_) {},
    );
  }
}

class _HarnessHandle {
  _HarnessHandle(this.key);

  final GlobalKey<_PanelHarnessState> key;

  _PanelHarnessState get state => key.currentState!;
  ReadingPanelCoordinatorState get coordinator =>
      state.coordinatorKey.currentState!;
  ReadingChromeState get chrome => state.chromeKey.currentState!;
}

Future<_HarnessHandle> _pumpHarness(
  WidgetTester tester, {
  required Future<List<ReadTheme>> Function() styleThemesLoader,
  WidgetBuilder? ttsBuilder,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_PanelHarnessState>();
  await pumpDesignSystem(
    tester,
    _PanelHarness(
      key: key,
      styleThemesLoader: styleThemesLoader,
      ttsBuilder: ttsBuilder ?? (_) => const Text('tts-panel'),
    ),
  );
  final handle = _HarnessHandle(key);
  handle.chrome.showBottomBar();
  await tester.pump();
  return handle;
}

Future<void> _openTool(
  WidgetTester tester,
  ReaderPanelToolCoordinates coordinates,
) async {
  await tester.tap(find.byTooltip(coordinates.tooltip));
  // 打开动画（150ms）计入打开过程，pumpAndSettle 等待动画完全结束。
  await tester.pumpAndSettle();
}

typedef ReaderPanelToolCoordinates = ({String tooltip});

const _styleTool = (tooltip: 'Style');
const _narratorTool = (tooltip: 'Narrator');

Finder get _panelSurface => find.byKey(readingToolPanelSurfaceKey);

Material _panelMaterial(WidgetTester tester) =>
    tester.widget<Material>(_panelSurface);

/// 面板子树里所有不透明且接近白色的绘制色（旧的“白色区域”回归断言）。
List<String> _opaqueNearWhiteColors(WidgetTester tester, Finder scope) {
  String hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
  final nearWhite = <String>[];
  final finders = <Finder>[
    find.descendant(of: scope, matching: find.byType(Material)),
    find.descendant(of: scope, matching: find.byType(ColoredBox)),
    find.descendant(of: scope, matching: find.byType(DecoratedBox)),
    find.descendant(of: scope, matching: find.byType(Card)),
  ];
  for (final finder in finders) {
    for (final element in finder.evaluate()) {
      Color? color;
      final widget = element.widget;
      if (widget is Material) color = widget.color;
      if (widget is ColoredBox) color = widget.color;
      if (widget is Card) color = widget.color;
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration) color = decoration.color;
      }
      if (color == null) continue;
      if (color.a < 0.9) continue;
      if (color.computeLuminance() < 0.8) continue;
      nearWhite.add('${widget.runtimeType}:${hex(color)}');
    }
  }
  return nearWhite;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  group('dark reading theme popup surface', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'readTheme': _darkReadThemeJson,
      });
      await Prefs().initPrefs();
    });

    testWidgets('style popup paints the reading surface with rounded corners',
        (tester) async {
      await _pumpHarness(
        tester,
        styleThemesLoader: () async => const <ReadTheme>[],
      );
      await _openTool(tester, _styleTool);

      expect(_panelSurface, findsOneWidget);
      final material = _panelMaterial(tester);
      expect(material.color, _darkReadingSurface);
      expect(material.color, isNot(const Color(0xFFFFFFFF)));
      expect(
        material.color!.computeLuminance(),
        lessThan(_allowedPanelBackgroundLuminance),
      );

      final panelTheme = Theme.of(
        tester.element(_panelSurface),
      );
      expect(panelTheme.colorScheme.surface, _darkReadingSurface);
      expect(panelTheme.colorScheme.onSurface, _darkReadingText);
      // 面板表面色与顶部工具栏同属阅读主题配色。
      expect(
        Theme.of(tester.element(find.byType(ReadingToolbar)))
            .colorScheme
            .surface,
        _darkReadingSurface,
      );

      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(of: _panelSurface, matching: find.byType(ClipRRect))
            .first,
      );
      final radius = clip.borderRadius.resolve(
        Directionality.of(tester.element(_panelSurface)),
      );
      expect(radius.topLeft.x, greaterThan(0));
      expect(radius.topRight.x, greaterThan(0));
      expect(radius.bottomLeft.x, 0);
      expect(radius.bottomRight.x, 0);

      expect(_opaqueNearWhiteColors(tester, _panelSurface), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrator popup inherits the reading surface', (tester) async {
      await _pumpHarness(
        tester,
        styleThemesLoader: () async => const <ReadTheme>[],
        ttsBuilder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('tts-root'),
            AppCard(child: const SizedBox(height: 120)),
          ],
        ),
      );
      await _openTool(tester, _narratorTool);

      expect(_panelSurface, findsOneWidget);
      expect(find.text('tts-root'), findsOneWidget);
      expect(_panelMaterial(tester).color, _darkReadingSurface);
      expect(
        Theme.of(tester.element(_panelSurface)).colorScheme.surface,
        _darkReadingSurface,
      );
      expect(_opaqueNearWhiteColors(tester, _panelSurface), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('light app theme no longer leaks its near-white surface',
        (tester) async {
      await _pumpHarness(
        tester,
        styleThemesLoader: () async => const <ReadTheme>[],
      );
      expect(_panelSurface, findsNothing);
      // 应用主题（旧弹层来源）仍是浅色。
      expect(
        Theme.of(tester.element(find.byType(ReadingChrome)))
            .colorScheme
            .surface,
        _appLightSurface,
      );
      await _openTool(tester, _styleTool);
      expect(_panelMaterial(tester).color, isNot(_appLightSurface));
      expect(_panelMaterial(tester).color, _darkReadingSurface);
    });

    testWidgets('popup surface follows a reading theme change while open',
        (tester) async {
      await _pumpHarness(
        tester,
        styleThemesLoader: () async => const <ReadTheme>[],
      );
      await _openTool(tester, _styleTool);
      expect(_panelMaterial(tester).color, _darkReadingSurface);

      Prefs().saveReadThemeToPrefs(
        ReadTheme(
          backgroundColor: 'FFFBFBF3',
          textColor: 'FF343434',
          backgroundImagePath: '',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_panelMaterial(tester).color, const Color(0xFFFBFBF3));
      expect(
        Theme.of(tester.element(_panelSurface)).colorScheme.onSurface,
        const Color(0xFF343434),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('popup open latency and animation', () {
    testWidgets('open settles under 300ms and includes the reveal animation',
        (tester) async {
      var loaderCalls = 0;
      SchedulerPhase? loaderPhase;
      await _pumpHarness(
        tester,
        styleThemesLoader: () async {
          loaderCalls++;
          loaderPhase = SchedulerBinding.instance.schedulerPhase;
          return const <ReadTheme>[];
        },
      );

      final stopwatch = Stopwatch()..start();
      await tester.tap(find.byTooltip('Style'));
      await tester.pump();
      final reveal = find
          .ancestor(of: _panelSurface, matching: find.byType(FadeTransition))
          .first;
      expect(reveal, findsOneWidget);
      expect(tester.widget<FadeTransition>(reveal).opacity.value, lessThan(1));
      // 首个 ticker tick 只建立时间基线；随后 75ms 处于动画中段。
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        tester.widget<FadeTransition>(reveal).opacity.value,
        inExclusiveRange(0, 1),
      );
      // 再推进 120ms（累计已超过 150ms 动画时长）后完全展开。
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<FadeTransition>(reveal).opacity.value, 1);
      await tester.pump();
      stopwatch.stop();

      // 打开耗时包含 150ms 打开动画，仍需低于 300ms。
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
      // 主题查询被推迟到首帧之后，不阻塞弹层首帧。
      expect(loaderCalls, 1);
      expect(loaderPhase, SchedulerPhase.postFrameCallbacks);
      expect(tester.takeException(), isNull);
    });

    testWidgets('style panel keeps state across rapid open/close cycles',
        (tester) async {
      var loaderCalls = 0;
      final handle = await _pumpHarness(
        tester,
        styleThemesLoader: () async {
          loaderCalls++;
          return <ReadTheme>[
            ReadTheme(
              id: 1,
              backgroundColor: 'FFFBFBF3',
              textColor: 'FF343434',
              backgroundImagePath: '',
            ),
          ];
        },
      );

      await _openTool(tester, _styleTool);
      expect(loaderCalls, 1);
      await tester.tap(find.text('open-style-subpage'));
      await tester.pump();
      expect(find.byKey(_themeSubpageKey), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        handle.chrome.hideBottomBar();
        await tester.pump();
        handle.chrome.showBottomBar();
        await tester.pump();
        handle.coordinator.showToolPanel(ReadingToolPanelKind.style);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        // 状态保活：二级页面在重复开关后仍在原处。
        expect(find.byKey(_themeSubpageKey), findsOneWidget);
      }

      // 首次打开 1 次 + 每次重开 1 次帧后静默刷新；没有同一次打开里重复加载。
      expect(loaderCalls, 6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid style/tts switching never throws or double-loads',
        (tester) async {
      var styleLoaderCalls = 0;
      var ttsBuilds = 0;
      final handle = await _pumpHarness(
        tester,
        styleThemesLoader: () async {
          styleLoaderCalls++;
          return const <ReadTheme>[];
        },
        ttsBuilder: (_) {
          ttsBuilds++;
          return const Text('tts-panel');
        },
      );

      for (var i = 0; i < 3; i++) {
        handle.coordinator.showToolPanel(ReadingToolPanelKind.style);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(_panelSurface, findsOneWidget);
        handle.coordinator.showToolPanel(ReadingToolPanelKind.tts);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('tts-panel'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // 每次打开样式面板至多触发一次主题加载（无同一打开内的重复初始化）。
      expect(styleLoaderCalls, lessThanOrEqualTo(3));
      expect(ttsBuilds, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('right-side style mode keeps working without the popup shell',
        (tester) async {
      final handle = await _pumpHarness(
        tester,
        styleThemesLoader: () async => const <ReadTheme>[],
      );
      handle.state.setStylePosition(AiPanelPositionEnum.right);
      await tester.pump();

      handle.coordinator.showToolPanel(ReadingToolPanelKind.style);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ReadingSidePanelHost), findsOneWidget);
      expect(find.text('style-root'), findsOneWidget);
      expect(_panelSurface, findsNothing);
      // 右侧面板继续使用应用主题背景（非弹层，不回归为阅读主题覆写）。
      expect(
        Theme.of(tester.element(find.byType(ReadingSidePanelHost)))
            .colorScheme
            .surface,
        _appLightSurface,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('TTS session gate first frame', () {
    testWidgets('starts session preparation only after the first frame',
        (tester) async {
      var calls = 0;
      var callsDuringBuild = -1;
      SchedulerPhase? phase;
      final initFinished = Completer<void>();
      await pumpDesignSystem(
        tester,
        Column(
          children: [
            TtsSessionGate(
              initialize: () async {
                calls++;
                phase = SchedulerBinding.instance.schedulerPhase;
                initFinished.complete();
              },
              builder: (_) => const Text('tts-content'),
            ),
            Builder(
              builder: (context) {
                callsDuringBuild = calls;
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      );
      // 首帧构建期间还没有开始 TTS 会话准备。
      expect(callsDuringBuild, 0);
      expect(calls, 1);
      expect(phase, SchedulerPhase.postFrameCallbacks);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('tts-content'), findsOneWidget);
      expect(calls, 1);
      expect(initFinished.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('skeleton is painted before the session future completes',
        (tester) async {
      final pending = Completer<void>();
      await pumpDesignSystem(
        tester,
        TtsSessionGate(
          initialize: () => pending.future,
          builder: (_) => const Text('tts-content'),
        ),
      );
      await tester.pump();
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.text('tts-content'), findsNothing);
      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('tts-content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
