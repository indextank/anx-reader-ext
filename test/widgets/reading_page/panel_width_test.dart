import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';

/// 宽度解析纯函数单元测试。
void main() {
  group('resolvePanelWidth', () {
    test('content width inside bounds is used as-is', () {
      expect(
        resolvePanelWidth(
          intrinsicWidth: 420,
          minWidth: StylePanelTokens.minPanelWidth,
          maxWidth: 560,
        ),
        420,
      );
    });

    test('below minimum clamps up to minimum', () {
      expect(
        resolvePanelWidth(
          intrinsicWidth: 180,
          minWidth: StylePanelTokens.minPanelWidth,
          maxWidth: 560,
        ),
        StylePanelTokens.minPanelWidth,
      );
    });

    test('above maximum clamps down to maximum (degrade to wrap)', () {
      expect(
        resolvePanelWidth(
          intrinsicWidth: 900,
          minWidth: StylePanelTokens.minPanelWidth,
          maxWidth: 560,
        ),
        560,
      );
    });

    test('boundary values equal bounds', () {
      expect(
        resolvePanelWidth(intrinsicWidth: 300, minWidth: 300, maxWidth: 560),
        300,
      );
      expect(
        resolvePanelWidth(intrinsicWidth: 560, minWidth: 300, maxWidth: 560),
        560,
      );
    });

    test('empty content still yields minimum', () {
      expect(
        resolvePanelWidth(intrinsicWidth: 0, minWidth: 300, maxWidth: 560),
        300,
      );
    });
  });

  group('panelMaxWidthFor', () {
    test('desktop width is capped by absolute cap minus inset', () {
      final max = panelMaxWidthFor(availableWidth: 1920);
      expect(
        max,
        StylePanelTokens.maxPanelWidthCap -
            StylePanelTokens.horizontalSafeInset,
      );
    });

    test('phone width uses factor minus safe inset', () {
      final max = panelMaxWidthFor(availableWidth: 400);
      // 0.72 * 400 - 16 = 272 < min 300 → 取下限。
      expect(max, StylePanelTokens.minPanelWidth);
      final widePhone = panelMaxWidthFor(availableWidth: 500);
      expect(widePhone, closeTo(500 * 0.72 - 16, 0.001));
    });

    test('never returns below minimum', () {
      expect(
        panelMaxWidthFor(availableWidth: 120),
        greaterThanOrEqualTo(StylePanelTokens.minPanelWidth),
      );
    });
  });

  group('measureTextWidth', () {
    const style = TextStyle(fontSize: 14);
    test('scales with textScaler', () {
      final w1 = measureTextWidth('自动', style, TextScaler.noScaling);
      final w13 = measureTextWidth(
        '自动',
        style,
        const TextScaler.linear(1.3),
      );
      final w15 = measureTextWidth(
        '自动',
        style,
        const TextScaler.linear(1.5),
      );
      expect(w13, greaterThan(w1));
      expect(w15, greaterThan(w13));
      expect(w13 / w1, closeTo(1.3, 0.05));
    });

    test('empty text has zero width', () {
      expect(measureTextWidth('', style, TextScaler.noScaling), 0);
    });

    test('longer text is wider', () {
      final short = measureTextWidth('横排', style, TextScaler.noScaling);
      final long = measureTextWidth('横排滚动方向', style, TextScaler.noScaling);
      expect(long, greaterThan(short));
    });
  });
}
