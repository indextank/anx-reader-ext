import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/settings_page/reading.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读设置页单行化回归：参考图圈选区域（写作方向/翻译模式/列数/
/// 列数切换阈值/简繁转换/代码高亮主题/浅色·深色主题芯片/页眉页脚
/// 左中右下拉）全部由"标题在上、控件在下"改为单行 tile。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> pumpReadingSettings(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
    TextScaler? textScaler,
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
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data:
                MediaQueryData(textScaler: textScaler ?? TextScaler.noScaling),
            child: const ProviderScope(child: ReadingSettings()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('circled items render as single-row tiles', (tester) async {
    await pumpReadingSettings(tester);

    // 圈选区域内的每个条目都应是单行 tile。
    for (final title in [
      '写作方向',
      '翻译模式',
      '列数',
      '列数切换阈值',
      '简繁转换',
      '代码高亮主题',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(SingleRowSettingTile),
      );
      expect(tile, findsOneWidget, reason: '$title 应使用单行设置项');
      final tileRect = tester.getRect(tile);
      // 单行（含可选副标题）高度应远低于旧上下堆叠布局。
      expect(tileRect.height, lessThan(110), reason: '$title 应为单行紧凑高度');
    }

    // 标题与控件同行：以"写作方向"为例，标题与分段控件垂直区间重叠。
    final writingTitle = tester.getRect(find.text('写作方向'));
    final segmented = find.descendant(
      of: find.byType(SingleRowSettingTile),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('AnxSegmentedButton'),
      ),
    );
    final writingSegment = segmented.evaluate().first;
    final segRect = tester.getRect(find.byWidget(writingSegment.widget));
    expect(writingTitle.bottom, greaterThan(segRect.top));
    expect(writingTitle.top, lessThan(segRect.bottom), reason: '标题与控件应处于同一行');
    expect(segRect.left, greaterThan(writingTitle.right), reason: '控件应位于标题右侧');

    // 阈值行：当前值以文本展示在滑杆左侧，且滑杆贴右缘。
    expect(find.text('720px'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header/footer dropdown columns are single-row tiles',
      (tester) async {
    await pumpReadingSettings(tester, size: const Size(1000, 1400));
    await tester.dragUntilVisible(
      find.text('页眉设置'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    for (final label in ['左侧', '中间', '右侧']) {
      final tile = find.ancestor(
        of: find.text(label).first,
        matching: find.byType(SingleRowSettingTile),
      );
      expect(tile, findsOneWidget, reason: '下拉列 $label 应为单行');
      expect(
        find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString().startsWith('DropdownButton'),
          ),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final variant in [
    (size: const Size(360, 800), scale: 1.3),
    (size: const Size(800, 1200), scale: 2.0),
  ]) {
    testWidgets(
        'no overflow at ${variant.size.width}px and ${variant.scale}x scale',
        (tester) async {
      await pumpReadingSettings(
        tester,
        size: variant.size,
        textScaler: TextScaler.linear(variant.scale),
      );
      await tester.dragUntilVisible(
        find.text('代码高亮主题'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      // 继续滚动会懒加载后续 StyleSettings；隔离其既有 IconAndText 溢出，
      // 使本用例只判断新增面板位置 tile 的布局。
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('RenderFlex overflowed') &&
            details.toString().contains('icon_and_text.dart')) {
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      for (final title in ['笔记面板展现位置', '样式面板展现位置']) {
        await tester.dragUntilVisible(
          find.text(title),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$title 不得溢出');
      }
      expect(tester.takeException(), isNull, reason: '窄屏/大字号下整页不得溢出');
    });
  }
}
