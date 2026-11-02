import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

/// WCAG 2.x 对比度：(L1 + 0.05) / (L2 + 0.05)，L1 为较亮一方的相对亮度。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _levels = [Level.SEVERE, Level.WARNING, Level.INFO];

Future<BuildContext> _pumpThemed(
    WidgetTester tester, Brightness brightness) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(
      brightness: brightness,
      seedColor: AppColors.defaultBrand,
    ),
    home: Builder(builder: (context) {
      captured = context;
      return const Scaffold(body: SizedBox());
    }),
  ));
  return captured;
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final label = brightness == Brightness.light ? 'light' : 'dark';
    testWidgets('log level pills meet 4.5:1 contrast ($label)', (tester) async {
      final context = await _pumpThemed(tester, brightness);

      for (final level in _levels) {
        final pair = logLevelColors(context, level);
        final ratio = contrastRatio(pair.background, pair.foreground);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$label ${level.name}: ${ratio.toStringAsFixed(2)}:1 '
              '(bg=${pair.background}, fg=${pair.foreground})',
        );
      }
    });
  }

  testWidgets('log level pills use semantic error/warning tokens',
      (tester) async {
    // 深色下 onError/onWarning 不是白色，能区分“写死白色前景”的回归。
    final context = await _pumpThemed(tester, Brightness.dark);
    final colors = context.appTheme.colors;

    final severe = logLevelColors(context, Level.SEVERE);
    expect(severe.background, colors.error);
    expect(severe.foreground, colors.onError);

    final warning = logLevelColors(context, Level.WARNING);
    expect(warning.background, colors.warning);
    expect(warning.foreground, colors.onWarning);
  });
}
