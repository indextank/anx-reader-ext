import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpDesignSystem(
  WidgetTester tester,
  Widget child, {
  bool eInkMode = false,
  TextScaler? textScaler,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ??
          AppTheme.build(
            brightness: Brightness.light,
            seedColor: AppColors.defaultBrand,
            eInkMode: eInkMode,
          ),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, app) {
        if (textScaler == null) return app!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: app!,
        );
      },
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
