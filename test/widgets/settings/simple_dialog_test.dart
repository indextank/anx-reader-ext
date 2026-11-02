import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/simple_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialogHost(
    WidgetTester tester, {
    NavigatorObserver? observer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [if (observer != null) observer],
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('save blocks duplicate submissions while pending',
      (tester) async {
    final completer = Completer<void>();
    var attempts = 0;
    Future<void> save(String value) {
      attempts++;
      return completer.future;
    }

    await pumpDialogHost(tester);
    showSimpleDialog('Language', save, [
      dialogOption('English', 'en', save),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.pump();

    expect(attempts, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('failed save stays open and offers a working retry',
      (tester) async {
    var attempts = 0;
    Future<void> save(String value) async {
      attempts++;
      if (attempts == 1) throw StateError('private failure');
    }

    await pumpDialogHost(tester);
    showSimpleDialog('Language', save, [
      dialogOption('English', 'en', save),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(attempts, 2);
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('pending disables every option and completes only the first save',
      (tester) async {
    final first = Completer<void>();
    final second = Completer<void>();
    final observer = _PopObserver();
    final attempts = <String>[];
    Future<void> save(String value) {
      attempts.add(value);
      return value == 'en' ? first.future : second.future;
    }

    await pumpDialogHost(tester, observer: observer);
    showSimpleDialog('Language', save, [
      dialogOption('English', 'en', save),
      dialogOption('Deutsch', 'de', save),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    SimpleDialogOption option(String label) => tester.widget(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SimpleDialogOption),
          ),
        );

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(option('English').onPressed, isNull);
    expect(option('Deutsch').onPressed, isNull);

    await tester.tap(find.text('Deutsch'));
    await tester.pump();
    expect(attempts, ['en']);

    second.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(observer.popCount, 0);
    expect(find.text('Language'), findsOneWidget);

    first.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(attempts, ['en']);
    expect(observer.popCount, 1);
    expect(find.text('Language'), findsNothing);
  });
}

class _PopObserver extends NavigatorObserver {
  var popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}
