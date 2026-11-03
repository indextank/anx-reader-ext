import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 红圈区域排版回归测试：
/// 1) 翻译面板：服务选择行"标签左、控件右"，语言行紧凑起始排列，
///    全部与卡片内容左缘对齐（修复前服务名/说明文字居中于面板中线、
///    语言行被两个 Expanded 平分导致文字悬浮半区中央）。
/// 2) AI 设置"AI 对话显示"分组：两个"标签 + 分段控件"行与页面统一
///    左缘对齐、分组卡片占满内容宽度（修复前卡片收缩为最宽子项宽度，
///    较窄的"面板位置"行在卡内被默认居中缩进）。
/// 覆盖宽/窄窗口、1.3 倍字号与深色主题，且均不得出现溢出异常。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.light,
    TextScaler? textScaler,
    required Widget child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget app = MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.build(
        brightness: brightness,
        seedColor: AppColors.defaultBrand,
      ),
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    );
    if (textScaler != null) {
      app = MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: app,
      );
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Finder appButtonByLabel(String label) => find.byWidgetPredicate(
        (w) => w is AppButton && w.label == label,
      );

  void expectTranslateAlignment(
    WidgetTester tester,
    double width, {
    bool full = true,
  }) {
    // 默认偏好下：服务 Bing 网页翻译，源语言 自动，目标 English。
    final caption = tester.getRect(find.text('当前服务').first);
    final service = tester.getRect(appButtonByLabel('Bing 网页翻译').first);
    final from = tester.getRect(appButtonByLabel('自动').first);

    // 1) "当前服务"标签与语言行按钮都起始对齐于卡片内容左缘
    //    （窄屏换行后同样保持起始对齐）。
    expect((from.left - caption.left).abs(), lessThan(0.5),
        reason: '语言行应与"当前服务"标签同一起始缘');
    expect(tester.takeException(), isNull,
        reason: '不得出现布局异常（含 RenderFlex overflow）');
    if (!full) return;

    final to = tester.getRect(appButtonByLabel('English').first);
    final arrow = tester.getRect(find.byIcon(Icons.arrow_forward_ios).first);

    // 2) 服务选择行为"标签左、控件右"，不再居中于面板中线。
    expect(service.left, greaterThan(caption.left), reason: '服务按钮应位于行尾（控件位）');
    expect(service.right, greaterThan(width / 2), reason: '服务按钮应贴行尾而非居中');
    // 3) 语言行紧凑排列：箭头紧随其后，整行宽度远小于半宽（无平分拉伸）。
    expect(arrow.left, greaterThan(from.right));
    expect(arrow.right, lessThan(to.left));
    expect(to.right - from.left, lessThan(width / 2),
        reason: '语言行不应被 Expanded 平分整行宽度');
  }

  for (final variant in [
    (size: const Size(1440, 900), scale: 1.0, dark: false, full: true),
    (size: const Size(800, 900), scale: 1.3, dark: false, full: true),
    // 360px + 1.3 倍：等宽测试字体比真实字体宽约 2.4 倍，服务名会
    // 换行；此变体断言换行后仍起始对齐且无溢出。
    (size: const Size(360, 800), scale: 1.3, dark: true, full: false),
  ]) {
    testWidgets(
        'translate panel alignment '
        '(${variant.size.width}px, ${variant.scale}x, '
        '${variant.dark ? 'dark' : 'light'})', (tester) async {
      await pumpAt(
        tester,
        size: variant.size,
        brightness: variant.dark ? Brightness.dark : Brightness.light,
        textScaler: TextScaler.linear(variant.scale),
        child: const TranslateSetting(),
      );
      expectTranslateAlignment(
        tester,
        variant.size.width.toDouble(),
        full: variant.full,
      );
    });
  }

  Finder segmentedFinder() => find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('AnxSegmentedButton'),
      );

  Rect sectionCardOf(WidgetTester tester, Finder inner) {
    var cardRect = Rect.zero;
    tester.element(inner).visitAncestorElements((e) {
      if (e.widget is Card && cardRect == Rect.zero) {
        cardRect = tester.getRect(find.byWidget(e.widget));
        return false;
      }
      return true;
    });
    expect(cardRect, isNot(Rect.zero), reason: '应能找到所在分组卡片');
    return cardRect;
  }

  for (final variant in [
    (size: const Size(1440, 900), scale: 1.0, dark: false),
    (size: const Size(420, 800), scale: 1.3, dark: true),
  ]) {
    testWidgets(
        'ai segmented rows alignment '
        '(${variant.size.width}px, ${variant.scale}x, '
        '${variant.dark ? 'dark' : 'light'})', (tester) async {
      await pumpAt(
        tester,
        size: variant.size,
        brightness: variant.dark ? Brightness.dark : Brightness.light,
        textScaler: TextScaler.linear(variant.scale),
        child: const ProviderScope(child: AISettings()),
      );
      await tester.dragUntilVisible(
        find.text('面板位置'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final label = tester.getRect(find.text('面板位置').first);
      // "面板位置"行与"显示模式"行（同类参照）共用统一左缘 24
      // （分组卡 margin 8 + tile 内容 padding 16）。
      expect(label.left, closeTo(24, 0.5), reason: '标签应与页面统一左缘对齐');

      final segmentRects = segmentedFinder()
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .where((r) => r.top >= label.top)
          .toList();
      expect(segmentRects, isNotEmpty, reason: '面板位置行下方应有分段控件');
      expect(segmentRects.first.left, closeTo(label.left, 0.5),
          reason: '分段控件应与其标签起始对齐');

      // 分组卡片应占满内容宽度，而不是收缩为最宽子项。
      final card = sectionCardOf(tester, find.text('面板位置').first);
      expect(card.width, greaterThan(variant.size.width - 40),
          reason: '分组卡片应占满内容宽度');

      expect(tester.takeException(), isNull);
    });
  }
}
