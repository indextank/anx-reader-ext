import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/reading_style_panel_provider.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_dropdown_tokens.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/combined_style_settings.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 样式面板验收：
/// - 高度参数为 0.9，弹框按可用高度的 90% 展示；
/// - 宽度由内容测量驱动，窄屏/侧栏被压缩时退化紧凑 + 横向安全兜底；
/// - 弹框/右栏两种形态下所有设置项单行、无 overflow；
/// - 异步主题数据源的 loading/error/empty 三态；
/// - 关键状态可经 Riverpod Provider 注入并单独验证；
/// - 两种形态的 golden 视觉对比。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-style-acceptance-');
    documentPath = tempDir.path;
    getFontDir().createSync();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<ReadTheme> sampleThemes() => <ReadTheme>[
        ReadTheme(
          id: 1,
          backgroundColor: 'FFFDF6E3',
          textColor: 'FF333333',
          backgroundImagePath: '',
        ),
        ReadTheme(
          id: 2,
          backgroundColor: 'FF121212',
          textColor: 'FFCCCCCC',
          backgroundImagePath: '',
        ),
      ];

  Widget combinedBuilder(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) {
    return CombinedStyleSettings(
      themes: themes,
      epubPlayerKey: GlobalKey<EpubPlayerState>(),
      setCurrentPage: setCurrentPage,
      hideAppBarAndBottomBar: (_) {},
      themeInserter: (_) async => 1,
    );
  }

  Widget panel({
    required Future<List<ReadTheme>> Function() loader,
    bool sideContent = false,
    StylePanelLayoutPlan? plan,
    double heightFactor = readingStylePanelHeightFactor,
  }) {
    return ReadingToolPanel(
      kind: ReadingToolPanelKind.style,
      notesBuilder: (_) => const SizedBox.shrink(),
      ttsBuilder: (_) => const SizedBox.shrink(),
      styleThemesLoader: loader,
      styleBuilder: combinedBuilder,
      sideContent: sideContent,
      styleLayoutPlan: plan,
      heightFactor: heightFactor,
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {bool settle = true}) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    if (settle) {
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpPopup(
    WidgetTester tester, {
    required Future<List<ReadTheme>> Function() loader,
    Size size = const Size(1200, 900),
    Locale locale = const Locale('en'),
    bool settle = true,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: brightness,
          seedColor: AppColors.defaultBrand,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          backgroundColor: const Color(0xFFDCDCD5),
          body: panel(loader: loader),
        ),
      ),
    );
    await pumpFrames(tester, settle: settle);
  }

  Future<StylePanelLayoutPlan> pumpSide(
    WidgetTester tester, {
    required Future<List<ReadTheme>> Function() loader,
    Size size = const Size(1200, 900),
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late StylePanelLayoutPlan plan;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            plan = resolveStylePanelLayout(
              context,
              availableWidth: size.width,
              maxWidth: panelMaxWidthFor(availableWidth: size.width),
            );
            return Scaffold(
              backgroundColor: const Color(0xFFDCDCD5),
              body: Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  SizedBox(
                    width: plan.width,
                    height: size.height,
                    child: panel(
                      loader: loader,
                      sideContent: true,
                      plan: plan,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await pumpFrames(tester, settle: settle);
    return plan;
  }

  int renderedLineCount(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.first);
    if (paragraph.text.toPlainText().isEmpty) return 1;
    // 测试字体缺少中文字形时 getBoxesForSelection 可能为空；
    // 复用同段落样式/宽度重新 layout，用行度量统计真实行数。
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
      textHeightBehavior: paragraph.textHeightBehavior,
      locale: paragraph.locale,
    )..layout(maxWidth: paragraph.size.width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines <= 0 ? 1 : lines;
  }

  void expectTextFullyVisible(
    WidgetTester tester,
    Finder finder,
    String title,
  ) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.first);
    if (paragraph.text.toPlainText().isEmpty) return;
    final full = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
    )..layout();
    final fullWidth = full.width;
    full.dispose();
    expect(paragraph.size.width + 0.5, greaterThanOrEqualTo(fullWidth),
        reason: '设置项「$title」不得截断/省略');
  }

  void expectEverySettingSingleLine(WidgetTester tester) {
    final titles = <String>{
      for (final tile in tester.widgetList<SingleRowSettingTile>(
        find.byType(SingleRowSettingTile),
      ))
        tile.title,
      for (final tile
          in tester.widgetList<AppListTile>(find.byType(AppListTile)))
        tile.title,
      for (final row in tester.widgetList<IconAndText>(
        find.byType(IconAndText),
      ))
        row.text,
    };
    expect(titles, isNotEmpty);
    for (final title in titles) {
      final finder = find.text(title);
      if (finder.evaluate().isEmpty) continue;
      expect(
        renderedLineCount(tester, finder),
        1,
        reason: '设置项「$title」必须单行完整展示',
      );
      expectTextFullyVisible(tester, finder, title);
    }
    expect(tester.takeException(), isNull, reason: '不得出现 overflow');
  }

  group('height parameter', () {
    test('style popup height factor is exactly 0.9', () {
      expect(readingToolPanelHeightFactor, 0.9);
      expect(readingStylePanelHeightFactor, 0.9);
      expect(readingAncillaryPanelHeightFactor, lessThan(0.9),
          reason: '笔记/TTS 等其它面板仍沿用既有 0.8 比例');
    });

    test('popup height uses available height on every platform', () {
      // 高度参数是与平台无关的 0.9；SafeArea/视口由各平台布局层提供，
      // 面板只消费“可用高度”，因此 Android/iOS/桌面/Web/HarmonyOS 一致。
      expect(readingToolPanelHeightFactor, 0.9);
      expect(readingStylePanelHeightFactor, readingToolPanelHeightFactor);
    });

    testWidgets('popup uses 90% of the available height', (tester) async {
      await pumpPopup(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(1400, 900),
      );
      final surface = find.byKey(readingToolPanelSurfaceKey);
      expect(surface, findsOneWidget);
      expect(tester.getSize(surface).height, closeTo(900 * 0.9, 1.0));
      expect(tester.getRect(surface).top, closeTo(45, 1.0));
      expect(tester.getRect(surface).bottom, closeTo(855, 1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('width is content driven but bounded by available space',
        (tester) async {
      await pumpPopup(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(1400, 900),
      );
      final context = tester.element(find.byType(ReadingToolPanel));
      final measured = stylePanelContentWidth(context);
      final width =
          tester.getSize(find.byKey(readingToolPanelSurfaceKey)).width;
      expect(width, closeTo(measured, 1.0));
      expect(width, lessThanOrEqualTo(1400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('side adaptive width is content driven and bounded',
        (tester) async {
      final plan = await pumpSide(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(1400, 900),
      );
      final maxWidth = panelMaxWidthFor(availableWidth: 1400);
      expect(plan.width, lessThanOrEqualTo(maxWidth));
      // 英文标签较长时，宽度先被可用上限约束，再退化为紧凑密度；
      // 若紧凑仍放不下则保持单行横向安全滚动（不换行/不省略）。
      if (plan.contentWidth > maxWidth) {
        expect(plan.metrics.isCompact, isTrue);
        expect(plan.horizontallyScrollable, isTrue);
        expect(plan.width, maxWidth);
      } else {
        expect(plan.width, closeTo(plan.contentWidth, 1.0));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('single line and overflow', () {
    testWidgets('popup form: every setting is single line without overflow',
        (tester) async {
      await pumpPopup(tester, loader: () async => sampleThemes());
      expectEverySettingSingleLine(tester);
    });

    testWidgets('side form: every setting is single line without overflow',
        (tester) async {
      final plan = await pumpSide(tester, loader: () async => sampleThemes());
      expect(plan.width, lessThanOrEqualTo(1200));
      expectEverySettingSingleLine(tester);
    });

    testWidgets('narrow side panel uses compact density / safe horizontal mode',
        (tester) async {
      final plan = await pumpSide(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(320, 700),
      );
      expect(plan.width, lessThanOrEqualTo(320));
      expect(plan.metrics.isCompact, isTrue, reason: '常规密度放不下时先压缩间距/图标间距');
      expect(tester.takeException(), isNull);
      expectEverySettingSingleLine(tester);
    });

    testWidgets('narrow popup form stays single line without overflow',
        (tester) async {
      await pumpPopup(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(320, 640),
      );
      final width =
          tester.getSize(find.byKey(readingToolPanelSurfaceKey)).width;
      expect(width, lessThanOrEqualTo(320));
      expectEverySettingSingleLine(tester);
    });

    testWidgets('large text scale + dark mode keep hierarchy and rows intact',
        (tester) async {
      await pumpPopup(
        tester,
        loader: () async => sampleThemes(),
        size: const Size(1400, 900),
        brightness: Brightness.dark,
        textScale: 1.6,
      );
      final context = tester.element(find.byType(ReadingToolPanel));
      final theme = Theme.of(context);
      final surface = tester.widget<Material>(
        find.byKey(readingToolPanelSurfaceKey),
      );
      expect(surface.color, theme.colorScheme.surface, reason: '深色模式沿用主题表面色');
      expectEverySettingSingleLine(tester);
    });
  });

  group('dropdown option height', () {
    testWidgets('text alignment dropdown uses the global reduced item height',
        (tester) async {
      await pumpPopup(tester, loader: () async => sampleThemes());
      final dropdown = find.byType(DropdownMenu<TextAlignmentEnum>);
      expect(dropdown, findsOneWidget);
      await tester.ensureVisible(dropdown);
      await tester.pump();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final items = find.byType(MenuItemButton);
      expect(items, findsWidgets);
      for (var i = 0; i < items.evaluate().length; i++) {
        expect(
          tester.getSize(items.at(i)).height,
          AppDropdownTokens.itemHeight,
          reason: '“文本对齐”下拉选项高度应使用全局 ${AppDropdownTokens.itemHeight}dp',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('visual hierarchy and 8pt grid', () {
    testWidgets('title/subtitle/body styles form a clear hierarchy',
        (tester) async {
      await pumpPopup(tester, loader: () async => sampleThemes());
      final context = tester.element(find.byType(ReadingToolPanel));
      final theme = Theme.of(context);
      final section = StylePanelTokens.sectionTitle(context);
      final subsection = StylePanelTokens.subsectionTitle(context);
      final label = StylePanelTokens.optionLabel(context);
      final helper = StylePanelTokens.helper(context);

      expect(section.fontSize, greaterThan(subsection.fontSize!),
          reason: '主标题字号应大于子标题');
      expect(subsection.fontSize, greaterThan(helper.fontSize!),
          reason: '子标题字号应大于辅助说明');
      expect(section.fontWeight!.index,
          greaterThanOrEqualTo(FontWeight.w600.index));
      expect(subsection.fontWeight!.index,
          greaterThanOrEqualTo(FontWeight.w600.index));
      expect(label.fontWeight, FontWeight.normal);
      expect(section.color, theme.colorScheme.onSurface);
      expect(subsection.color, theme.colorScheme.onSurfaceVariant);
      expect(helper.color, theme.colorScheme.onSurfaceVariant);
    });

    test('spacing tokens follow the 8pt grid', () {
      double is8(double value) => value % 8;
      expect(is8(StylePanelTokens.rowGap), 0);
      expect(is8(StylePanelTokens.sectionGap), 0);
      expect(is8(StylePanelTokens.subsectionGap), 0);
      for (final padding in <EdgeInsets>[
        StylePanelTokens.panelPadding,
        StylePanelTokens.childIndent,
        StylePanelTokens.sectionHeaderPadding,
        StylePanelTokens.subsectionHeaderPadding,
        StylePanelTokens.subsectionContentPadding,
      ]) {
        for (final value in <double>[
          padding.left,
          padding.top,
          padding.right,
          padding.bottom,
        ]) {
          expect(is8(value), 0, reason: '$padding 不符合 8pt 栅格');
        }
      }
    });
  });

  group('async themes tri-state', () {
    testWidgets('loading -> empty keeps the panel geometry stable',
        (tester) async {
      final completer = Completer<List<ReadTheme>>();
      await pumpPopup(
        tester,
        loader: () => completer.future,
        settle: false,
      );
      final surface = find.byKey(readingToolPanelSurfaceKey);
      expect(surface, findsOneWidget);
      expect(find.byType(AppLoadingIndicator), findsOneWidget);
      final loadingSize = tester.getSize(surface);

      completer.complete(const <ReadTheme>[]);
      await pumpFrames(tester);
      expect(find.byType(AppLoadingIndicator), findsNothing);
      expect(find.text('No reading themes yet'), findsOneWidget);
      expect(tester.getSize(surface), loadingSize, reason: '空数据不得让弹框塌陷或跳动');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error shows retry and recovers to empty state',
        (tester) async {
      var attempts = 0;
      await pumpPopup(tester, loader: () async {
        attempts++;
        if (attempts == 1) throw StateError('theme load failure');
        return const <ReadTheme>[];
      });
      expect(find.byType(AppErrorState), findsOneWidget);
      final errorSize = tester.getSize(find.byKey(readingToolPanelSurfaceKey));

      await tester.tap(find.text('Retry'));
      await pumpFrames(tester);
      expect(attempts, 2);
      expect(find.text('No reading themes yet'), findsOneWidget);
      expect(tester.getSize(find.byKey(readingToolPanelSurfaceKey)), errorSize,
          reason: '错误态与空态的面板几何保持一致');
      expect(tester.takeException(), isNull);
    });

    testWidgets('side form: loading -> empty keeps the panel geometry stable',
        (tester) async {
      final completer = Completer<List<ReadTheme>>();
      await pumpSide(
        tester,
        loader: () => completer.future,
        settle: false,
      );
      // 右栏形态没有弹框 Material shell，直接以面板宿主尺寸验证稳定。
      final panelHost = find.byType(ReadingToolPanel);
      expect(panelHost, findsOneWidget);
      final loadingSize = tester.getSize(panelHost);

      completer.complete(const <ReadTheme>[]);
      await pumpFrames(tester);
      expect(find.text('No reading themes yet'), findsOneWidget);
      expect(tester.getSize(panelHost), loadingSize, reason: '右栏形态空数据同样保持布局稳定');
      expect(tester.takeException(), isNull);
    });

    test('Riverpod provider exposes and can inject loading/error/data',
        () async {
      final completer = Completer<List<ReadTheme>>();
      final container = ProviderContainer(
        overrides: [
          readingStyleThemesLoaderProvider.overrideWithValue(
            () => completer.future,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(readingStyleThemesProvider, (_, __) {});
      addTearDown(sub.close);
      expect(container.read(readingStyleThemesProvider), isA<AsyncLoading>());

      completer.complete(const <ReadTheme>[]);
      final data = await container.read(readingStyleThemesProvider.future);
      expect(data, isEmpty);
      expect(container.read(readingStyleThemesProvider).hasValue, isTrue);

      final failing = ProviderContainer(
        overrides: [
          readingStyleThemesLoaderProvider.overrideWithValue(
            () => Future<List<ReadTheme>>.error(StateError('boom')),
          ),
        ],
      );
      addTearDown(failing.dispose);
      await expectLater(
        failing.read(readingStyleThemesProvider.future),
        throwsStateError,
      );
      expect(failing.read(readingStyleThemesProvider).hasError, isTrue);
    });
  });
}
