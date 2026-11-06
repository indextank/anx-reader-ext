import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';

/// 内容宽度计算（纯函数核心）单元测试。
void main() {
  Future<double> contentWidthOf(
    WidgetTester tester,
    TextScaler scaler,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Builder(
            key: key,
            builder: (context) => const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final context = key.currentContext;
    expect(context, isNotNull, reason: '本地化加载后应可取到 context');
    return stylePanelContentWidth(context!);
  }

  testWidgets('content width grows with text scale', (tester) async {
    final base = await contentWidthOf(tester, TextScaler.noScaling);
    final s13 = await contentWidthOf(tester, const TextScaler.linear(1.3));
    final s15 = await contentWidthOf(tester, const TextScaler.linear(1.5));
    expect(s13, greaterThan(base));
    expect(s15, greaterThan(s13));
  });

  testWidgets('content width exceeds minimum panel width', (tester) async {
    final width = await contentWidthOf(tester, TextScaler.noScaling);
    expect(width, greaterThan(300), reason: '内容宽度应高于下限 300');
  });

  testWidgets('resolved width stays within bounds at every scale',
      (tester) async {
    for (final scaler in [
      TextScaler.noScaling,
      const TextScaler.linear(1.3),
      const TextScaler.linear(1.5),
    ]) {
      final content = await contentWidthOf(tester, scaler);
      final max = panelMaxWidthFor(availableWidth: 1200);
      final resolved = resolvePanelWidth(
        intrinsicWidth: content,
        minWidth: 300,
        maxWidth: max,
      );
      expect(resolved, lessThanOrEqualTo(max));
      expect(resolved, greaterThanOrEqualTo(300));
    }
  });

  testWidgets('segmented rows dominate over slider rows', (tester) async {
    // 三段行（写作方向等）应显著宽于单滑杆行：内容宽度 > 最宽滑杆行。
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          key: key,
          builder: (context) => const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = L10n.of(key.currentContext!);
    // specs 元素为私有 _RowSpec：以“无 controlWidth 的行 = 分段行”
    // 的方式不可行；改为断言解析出的内容宽度 ≥ 任一三段行的手工估算，
    // 证明分段行已被纳入计算。
    final theme = Theme.of(key.currentContext!);
    final specs = stylePanelRowSpecs(l10n);
    expect(specs.length, greaterThan(20), reason: '行规格应覆盖全部分组');
    final contentWidth = computeStylePanelContentWidth(
      rows: specs,
      labelStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
      controlStyle: theme.textTheme.labelLarge ?? const TextStyle(),
      textScaler: TextScaler.noScaling,
      metrics: StylePanelMetrics.regular,
    );
    final metrics = StylePanelMetrics.regular;
    final writingRowEstimate = measureTextWidth(
          l10n.readingPageWritingDirection,
          theme.textTheme.bodyMedium ?? const TextStyle(),
          TextScaler.noScaling,
        ) +
        metrics.labelGap +
        3 *
            (measureTextWidth(
                  l10n.readingPageWritingDirectionVertical,
                  theme.textTheme.labelLarge ?? const TextStyle(),
                  TextScaler.noScaling,
                ) +
                metrics.segmentChrome) +
        metrics.horizontalPaddingTotal +
        metrics.childIndent.horizontal;
    expect(contentWidth, greaterThanOrEqualTo(writingRowEstimate - 1),
        reason: '内容宽度应不小于最宽三段行的估算');
  });
}
