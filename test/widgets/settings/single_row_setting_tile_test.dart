import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> pumpTile(
    WidgetTester tester, {
    required Size size,
    TextScaler? textScaler,
    TextDirection direction = TextDirection.ltr,
    required Widget child,
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
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                  textScaler: textScaler ?? TextScaler.noScaling),
              child: child,
            ),
          ),
        ),
      ),
    );
    // 骨架占位带持续脉冲动画，pumpAndSettle 永不落定，用固定 pump。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 模拟分段按钮宽度的控件（三段、约 240dp 固有宽）。
  Widget wideControl() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final i in [1, 2, 3])
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                width: 72,
                height: 32,
                color: Colors.blue,
                child: Text('seg$i'),
              ),
            ),
        ],
      );

  testWidgets('title left, trailing right, vertically centered, >=48dp',
      (tester) async {
    await pumpTile(
      tester,
      size: const Size(800, 200),
      child: const SingleRowSettingTile(
        title: '写作方向',
        trailing: SizedBox(
            width: 48, height: 48, child: ColoredBox(color: Colors.blue)),
      ),
    );

    final titleRect = tester.getRect(find.text('写作方向'));
    final trailing = find.byType(SizedBox).first;
    final trailingRect = tester.getRect(trailing);
    final tileRect = tester.getRect(find.byType(SingleRowSettingTile));

    expect(titleRect.left, lessThan(trailingRect.left), reason: '标题应在左');
    expect(trailingRect.right, greaterThan(800 - 40),
        reason: '控件应贴右缘（padding 16 内）');
    expect(
      (titleRect.center.dy - trailingRect.center.dy).abs(),
      lessThan(4),
      reason: '标题与控件垂直居中对齐',
    );
    expect(tileRect.height, greaterThanOrEqualTo(48), reason: '整行最小高度不小于 48dp');
    expect(tester.takeException(), isNull);
  });

  testWidgets('long title ellipsizes and control keeps space', (tester) async {
    final control = wideControl();
    await pumpTile(
      tester,
      size: const Size(320, 200),
      child: SingleRowSettingTile(
        title: '列数切换阈值' * 12,
        trailing: control,
      ),
    );

    final title = tester.widget<Text>(find.text('列数切换阈值' * 12));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    final tileRect = tester.getRect(find.byType(SingleRowSettingTile));
    // 控件包裹在受限视口的横向滚动中：视口受最大宽度约束，内容按
    // 固有宽滚动，布局上永不溢出。
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(viewport.width, lessThan(tileRect.width * 0.72),
        reason: '非钉合控件视口宽度受最大宽度约束');
    expect(viewport.right, greaterThan(tileRect.right - 40),
        reason: '控件区域贴行右缘');
    expect(tester.takeException(), isNull, reason: '窄屏 + 长标题不得溢出');
  });

  testWidgets('row tap fires callback across the whole row', (tester) async {
    var taps = 0;
    await pumpTile(
      tester,
      size: const Size(600, 200),
      child: SingleRowSettingTile(
        title: '列数',
        onTap: () => taps++,
        trailing: wideControl(),
      ),
    );

    await tester.tap(find.text('列数'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.tap(find.byType(SingleRowSettingTile));
    await tester.pumpAndSettle();
    expect(taps, 2, reason: '整行热区均可触发回调');
  });

  testWidgets('disabled tile does not fire callbacks', (tester) async {
    var taps = 0;
    await pumpTile(
      tester,
      size: const Size(600, 200),
      child: SingleRowSettingTile(
        title: '翻译模式',
        enabled: false,
        onTap: () => taps++,
        trailing: wideControl(),
      ),
    );

    await tester.tap(find.text('翻译模式'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(taps, 0);
    final listTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(listTile.enabled, isFalse, reason: '禁用兜底：值不可用时进入禁用态');
  });

  testWidgets('loading shows a single-line skeleton placeholder',
      (tester) async {
    await pumpTile(
      tester,
      size: const Size(600, 200),
      child: SingleRowSettingTile(
        title: '浅色主题',
        loading: true,
        valueLabel: '720px',
      ),
    );

    expect(find.byType(AppSkeleton), findsOneWidget);
    // 占位以 valueLabel 为形状（Skeletonizer 保留 Text 仅替换绘制），
    // 且语义被排除、不参与交互。
    expect(
      find.descendant(
        of: find.byType(AppSkeleton),
        matching: find.text('720px'),
      ),
      findsOneWidget,
      reason: '加载值应作为骨架形状而非可交互控件展示',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned slider fills remaining width next to value label',
      (tester) async {
    await pumpTile(
      tester,
      size: const Size(600, 200),
      child: SingleRowSettingTile(
        title: '列数切换阈值',
        valueLabel: '720px',
        pinnedTrailing: true,
        trailing: Slider(
          value: 0.5,
          min: 0,
          max: 1,
          onChanged: (_) {},
        ),
      ),
    );

    final slider = tester.getRect(find.byType(Slider));
    final tile = tester.getRect(find.byType(SingleRowSettingTile));
    expect(slider.right, greaterThan(tile.right - 40), reason: '滑杆占满剩余宽度并贴右缘');
    expect(find.text('720px'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 600.0, 1024.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          'no overflow at ${width.toInt()}px width and ${scale}x text scale',
          (tester) async {
        await pumpTile(
          tester,
          size: Size(width, 300),
          textScaler: TextScaler.linear(scale),
          child: SingleRowSettingTile(
            title: '写作方向写作方向写作方向',
            subtitle: '仅阅读时可用，每本书独立设置',
            trailing: wideControl(),
          ),
        );
        expect(tester.takeException(), isNull, reason: '任意屏宽 × 1.0–2.0 缩放不得溢出');
      });
    }
  }

  testWidgets('RTL mirrors the row without errors', (tester) async {
    final control = wideControl();
    await pumpTile(
      tester,
      size: const Size(600, 200),
      direction: TextDirection.rtl,
      child: SingleRowSettingTile(
        title: '写作方向',
        trailing: control,
      ),
    );

    final titleRect = tester.getRect(find.text('写作方向'));
    final controlRect = tester.getRect(find.byWidget(control));
    expect(titleRect.left, greaterThan(controlRect.left),
        reason: 'RTL 下标题应位于控件右侧（镜像）');
    expect(tester.takeException(), isNull);
  });
}
