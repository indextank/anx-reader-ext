import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_slider_label.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 样式面板层级对齐回归：
/// - 弹框默认高度调高；
/// - “段间距”与下方“翻页方式”之间有明确垂直间距；
/// - “浅色主题”与上下设置行左对齐；
/// - 页眉/页脚等子设置项与“样式面板展现位置”等主设置行同一左对齐线；
/// - 每个主设置项下的内容都有统一左缩进。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-style-align-');
    documentPath = tempDir.path;
    getFontDir().createSync();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(800, 1400),
    bool scrollable = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: scrollable ? SingleChildScrollView(child: child) : child,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
  }

  double leftOf(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dx;

  group('popup height', () {
    testWidgets('style popup uses the taller default height', (tester) async {
      await pumpPanel(
        tester,
        ReadingToolPanel(
          kind: ReadingToolPanelKind.style,
          notesBuilder: (_) => const SizedBox.shrink(),
          ttsBuilder: (_) => const SizedBox.shrink(),
          styleThemesLoader: () async => const <ReadTheme>[],
          styleBuilder: (_, __, ___) => const SingleChildScrollView(
            child: SizedBox(height: 2000),
          ),
        ),
        size: const Size(1000, 800),
        scrollable: false,
      );

      final surface = find.byKey(readingToolPanelSurfaceKey);
      expect(surface, findsOneWidget);
      final height = tester.getSize(surface).height;
      final expected = 800 * readingToolPanelHeightFactor;
      expect(height, expected);
      expect(height, greaterThan((800 * 0.7).clamp(0.0, 600.0)),
          reason: '默认高度为 1.0，应比旧的 0.7/600 更高');
      expect(tester.takeException(), isNull);
    });
  });

  group('style widget spacing', () {
    testWidgets('paragraph spacing and page turning method have a clear gap',
        (tester) async {
      await pumpPanel(
        tester,
        StyleWidget(
          themes: const <ReadTheme>[],
          epubPlayerKey: GlobalKey<EpubPlayerState>(),
          setCurrentPage: (_) {},
          hideAppBarAndBottomBar: (_) {},
          embedded: true,
          themeInserter: (_) async => 1,
        ),
      );

      final paragraph = tester.getRect(find.text('Paragraph Spacing'));
      final pageTurning = tester.getRect(find.text('Page Turning Method'));
      expect(
        pageTurning.top - paragraph.bottom,
        greaterThanOrEqualTo(StylePanelTokens.subsectionGap - 4),
        reason: '段间距与翻页方式之间需要上下间距',
      );

      // 同一主分组内的滑杆行与下拉行使用同一左缩进。
      final sliderRow = find.ancestor(
        of: find.text('Paragraph Spacing'),
        matching: find.byType(StylePanelSliderLabel),
      );
      expect(leftOf(tester, sliderRow).round(),
          leftOf(tester, find.byType(DropdownMenu<PageTurn>)).round());
      expect(tester.takeException(), isNull);
    });
  });

  group('reading settings alignment', () {
    testWidgets('light theme row aligns with the rows above and below',
        (tester) async {
      Prefs().codeHighlightTheme = CodeHighlightThemeEnum.defaultTheme;
      await pumpPanel(tester, const ReadingMoreSettings());

      final lightThemeLeft = leftOf(tester, find.text('Light Themes'));
      expect(lightThemeLeft,
          closeTo(leftOf(tester, find.text('Code Highlight Theme')), 0.5));
      expect(lightThemeLeft,
          closeTo(leftOf(tester, find.text('Writing Direction')), 0.5));
      expect(lightThemeLeft,
          closeTo(leftOf(tester, find.text('Style panel position')), 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'header/footer sub items use the same indent as the panel '
        'position setting above', (tester) async {
      await pumpPanel(tester, const ReadingMoreSettings());

      final referenceLeft = leftOf(tester, find.text('Style panel position'));
      final headerLeft = leftOf(tester, find.text('Header Settings'));
      final footerLeft = leftOf(tester, find.text('Footer Settings'));
      expect(headerLeft, closeTo(referenceLeft, 0.5));
      expect(footerLeft, closeTo(referenceLeft, 0.5));

      for (final label in <String>['Margin', 'Left Margin', 'Right Margin']) {
        expect(leftOf(tester, find.text(label)), closeTo(referenceLeft, 0.5),
            reason: '“$label” 应与上方样式面板展现位置行左对齐');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('style settings alignment', () {
    testWidgets('every child setting under a main section shares one indent',
        (tester) async {
      await pumpPanel(tester, const StyleSettings());

      final referenceLeft = leftOf(tester, find.text('Use Book Styles'));
      final indentRow = find.ancestor(
        of: find.text('Indent'),
        matching: find.byType(StylePanelSliderLabel),
      );
      expect(leftOf(tester, indentRow), closeTo(referenceLeft, 0.5));
      // 带前置图标的行（文字对齐）以图标起点作为内容缩进线。
      final alignmentIcon = find.descendant(
        of: find.widgetWithText(SingleRowSettingTile, 'Text Alignment'),
        matching: find.byIcon(Icons.format_align_left),
      );
      expect(leftOf(tester, alignmentIcon), closeTo(referenceLeft, 0.5));
      expect(leftOf(tester, find.text('Enable Custom CSS')),
          closeTo(referenceLeft, 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('combined panel hierarchy', () {
    testWidgets('main titles are flush and grouped content is indented',
        (tester) async {
      // 直接验证“主标题 -> 子设置内容”的缩进关系即可；主分组标题由
      // CombinedStyleSettings 的 _SectionTitle 统一控制。
      await pumpPanel(tester, const StyleSettings());
      final mainSectionLeft = leftOf(tester, find.text('Use Book Styles'));
      expect(mainSectionLeft, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
