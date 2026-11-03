import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全库单行化扫尾：AI 设置（显示模式/面板位置）与外观页
/// （字号缩放/封面宽度/分组样式）由上下堆叠改为单行 tile。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    TextScaler? textScaler,
    required Widget child,
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
            data: MediaQueryData(
              textScaler: textScaler ?? TextScaler.noScaling,
            ),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('ai display mode and panel position are single-row tiles',
      (tester) async {
    await pumpAt(
      tester,
      size: const Size(900, 1200),
      child: const ProviderScope(child: AISettings()),
    );
    await tester.dragUntilVisible(
      find.text('面板位置'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    for (final title in ['显示模式', '面板位置']) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(SingleRowSettingTile),
      );
      expect(tile, findsOneWidget, reason: '$title 应为单行设置项');
      final tileRect = tester.getRect(tile);
      expect(tileRect.height, lessThan(96), reason: '$title 应为单行高度');
      final titleRect = tester.getRect(find.text(title));
      expect(titleRect.left, closeTo(24, 0.5), reason: '$title 应与页面统一左缘对齐');
    }

    // 标题与分段控件同行：面板位置 tile 内控件在标题右侧且垂直区间重叠。
    final label = tester.getRect(find.text('面板位置'));
    final panelTile = find.ancestor(
      of: find.text('面板位置'),
      matching: find.byType(SingleRowSettingTile),
    );
    final segRect = tester.getRect(
      find.descendant(
        of: panelTile,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('AnxSegmentedButton'),
        ),
      ),
    );
    expect(segRect.left, greaterThan(label.right), reason: '控件在标题右侧');
    expect(label.bottom, greaterThan(segRect.top));
    expect(label.top, lessThan(segRect.bottom), reason: '标题与控件同行');
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance text scale slider row is single-row', (tester) async {
    await pumpAt(
      tester,
      size: const Size(900, 1200),
      child: const ProviderScope(child: AppearanceSetting()),
    );

    final tile = find.ancestor(
      of: find.text('界面字号'),
      matching: find.byType(SingleRowSettingTile),
    );
    expect(tile, findsOneWidget);
    expect(find.text('100%'), findsOneWidget, reason: '当前值应展示在行内');

    final slider = tester.getRect(find.byType(Slider).first);
    final tileRect = tester.getRect(tile);
    expect(slider.right, greaterThan(tileRect.right - 40),
        reason: '滑杆应占满剩余宽度贴右缘');
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance cover width and folder style rows are single-row',
      (tester) async {
    await pumpAt(
      tester,
      size: const Size(900, 1400),
      child: const ProviderScope(child: AppearanceSetting()),
    );
    await tester.dragUntilVisible(
      find.text('书架文件夹样式'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    for (final title in ['封面宽度', '书架文件夹样式']) {
      expect(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SingleRowSettingTile),
        ),
        findsOneWidget,
        reason: title,
      );
    }
    expect(find.byType(Slider), findsAtLeastNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final variant in [
    (size: const Size(360, 900), scale: 1.3, page: 0),
    (size: const Size(800, 1200), scale: 2.0, page: 0),
    (size: const Size(360, 900), scale: 1.3, page: 1),
    (size: const Size(800, 1200), scale: 2.0, page: 1),
  ]) {
    testWidgets(
        'no overflow page${variant.page} at ${variant.size.width}px '
        '${variant.scale}x', (tester) async {
      await pumpAt(
        tester,
        size: variant.size,
        textScaler: TextScaler.linear(variant.scale),
        child: variant.page == 0
            ? const ProviderScope(child: AISettings())
            : const ProviderScope(child: AppearanceSetting()),
      );
      if (variant.page == 0) {
        await tester.dragUntilVisible(
          find.text('面板位置'),
          find.byType(ListView),
          const Offset(0, -200),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
