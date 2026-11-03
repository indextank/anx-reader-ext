import 'dart:io';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


/// 日志列表紧凑化与级别筛选回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final logFile = File(
    '${Directory.systemTemp.createTempSync('anx-log-compact').path}'
    '${Platform.pathSeparator}anx_reader.log',
  )..writeAsStringSync(
      'INFO^*^ 2024-01-01T10:00:00.000^*^ app started\n'
      'SEVERE^*^ 2024-01-01T10:01:00.000^*^ boom failure\n'
      'WARNING^*^ 2024-01-01T10:02:00.000^*^ careful\n'
      'INFO^*^ 2024-01-02T11:00:00.000^*^ second day entry\n',
    );

  Future<void> pumpLogs(
    WidgetTester tester, {
    TextScaler? textScaler,
    Size size = const Size(800, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler ?? TextScaler.noScaling),
          child: LogPage(
            loadLogFile: () async => logFile,
            readLogLines: (file) async => file.readAsLinesSync(),
          ),
        ),
      ),
    );
    // 异步加载链跨多个事件循环回合，多帧推进后再 settle。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('compact entries show level, time and message together',
      (tester) async {
    await pumpLogs(tester);

    expect(find.textContaining('app started'), findsOneWidget);
    expect(find.textContaining('boom failure'), findsOneWidget);
    expect(find.textContaining('careful'), findsOneWidget);

    // 头部一行：级别胶囊 + 时间 + 复制图标与标题文本垂直区间重叠。
    final level = tester.getRect(find.text('SEVERE').first);
    final time = tester.getRect(find.text('10:01:00'));
    final message = tester.getRect(find.textContaining('boom failure'));
    expect(time.top, closeTo(level.top, 6), reason: '级别与时间同行');
    expect(message.top, greaterThan(time.bottom), reason: '消息在头部之下');

    // 紧凑高度：单行消息的条目应远低于旧堆叠布局（约 190px）。
    final tile = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('boom failure'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(tile.height, lessThan(120), reason: '紧凑条目高度');

    // 复制按钮保留（图标 + tooltip）。
    expect(find.byTooltip('Copy'), findsNWidgets(4), reason: '每条日志保留复制按钮');
    expect(tester.takeException(), isNull);
  });

  testWidgets('date is shown only on day change', (tester) async {
    await pumpLogs(tester);
    // 第二天首条带日期，其余仅时间。
    expect(find.text('10:00:00'), findsOneWidget);
    expect(find.text('01-02 11:00:00'), findsOneWidget);
    expect(find.textContaining('01-02'), findsOneWidget);
  });

  testWidgets('filter defaults to ALL and narrows by level', (tester) async {
    await pumpLogs(tester);

    // 默认 ALL：全部可见，ALL 段选中。
    expect(find.text('ALL'), findsOneWidget);
    expect(find.textContaining('app started'), findsOneWidget);
    expect(find.textContaining('boom failure'), findsOneWidget);

    // 切到 SEVERE：仅保留严重日志（点击筛选分段，级别胶囊同名需限定）。
    final segmented = find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('AnxSegmentedButton'),
    );
    await tester.tap(
      find.descendant(of: segmented, matching: find.text('SEVERE')).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('boom failure'), findsOneWidget);
    expect(find.textContaining('app started'), findsNothing);
    expect(find.textContaining('careful'), findsNothing);

    // 切回 ALL：全部恢复。
    await tester.tap(find.text('ALL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('app started'), findsOneWidget);
    expect(find.textContaining('careful'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact list fits 1.3 text scale on narrow screens',
      (tester) async {
    await pumpLogs(
      tester,
      size: const Size(360, 800),
      textScaler: const TextScaler.linear(1.3),
    );
    expect(find.textContaining('boom failure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
