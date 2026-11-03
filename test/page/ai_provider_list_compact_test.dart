import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

/// 供应商列表紧凑化与排序回归：
/// 1) 已启用的供应商排在未启用之前，当前默认项排最前，同级保持原序；
/// 2) URL/警告并入首行标题列（单行省略），操作行仅在存在动作时渲染，
///    卡片高度较原四行堆叠布局明显降低；
/// 3) 1.3 倍字号紧凑视口下无溢出异常。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester, {
    required List<AiProvider> providers,
    Map<String, Object> initialPrefs = const {},
    TextScaler? textScaler,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    await Prefs().initPrefs();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          aiProvidersProvider.overrideWith(
            () => _StaticAiProviders(providers),
          ),
        ],
        child: const AiProviderListPage(),
      ),
      textScaler: textScaler,
    );
  }

  AiProvider provider(
    String id,
    String title, {
    bool enabled = true,
    bool isBuiltin = false,
  }) =>
      AiProvider(
        id: id,
        title: title,
        url: 'https://$id.example.com/v1/chat/completions',
        protocol: AiProtocol.openai,
        enabled: enabled,
        isBuiltin: isBuiltin,
      );

  testWidgets('enabled and default providers sort to the front',
      (tester) async {
    await pumpPage(
      tester,
      providers: [
        provider('off-a', 'Off A', enabled: false, isBuiltin: true),
        provider('on-b', 'On B', isBuiltin: true),
        provider('off-c', 'Off C', enabled: false, isBuiltin: true),
        provider('on-d', 'On D', isBuiltin: true),
      ],
      // 默认项选中 On D：应排最前；随后是启用的 On B；最后按原序 Off A、Off C。
      initialPrefs: {'selectedAiService': 'on-d'},
    );

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.startsWith(RegExp('Off|On')))
        .toList();
    expect(titles.take(4), ['On D', 'On B', 'Off A', 'Off C']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default builtin card drops the action row and keeps compact',
      (tester) async {
    await pumpPage(
      tester,
      providers: [
        provider('default', 'Default One', isBuiltin: true),
        provider('other', 'Other Two', isBuiltin: true),
        provider('custom', 'Custom provider'),
      ],
      initialPrefs: {'selectedAiService': 'default'},
    );

    // 默认项：无"设为默认"按钮（Chip 徽标在标题行内），无独立操作行。
    final defaultCard = find.ancestor(
        of: find.text('Default One'), matching: find.byType(AppCard));
    expect(
      find.descendant(
        of: defaultCard,
        matching: find.byType(AppButton),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: defaultCard,
        matching: find.text('Default'),
      ),
      findsOneWidget,
    );

    // URL 单行省略，并入首行；两卡高度均低于旧的独立 URL/警告行布局。
    final urlText = tester.widget<Text>(find.text(
      'https://default.example.com/v1/chat/completions',
    ));
    expect(urlText.maxLines, 1);
    expect(urlText.overflow, TextOverflow.ellipsis);

    final defaultRect = tester.getRect(defaultCard);
    final otherRect = tester.getRect(
      find.ancestor(of: find.text('Other Two'), matching: find.byType(AppCard)),
    );
    // 原四行堆叠布局（标题/URL/警告/操作各占一行）下同卡片约 190px+。
    expect(defaultRect.height, lessThan(145), reason: '默认内置供应商卡片应只有首行，高度最紧凑');
    expect(otherRect.height, lessThan(185), reason: '带操作行的卡片也应低于原四行堆叠高度');
    // 两卡高度差应约为"操作行 + 间距"（s4 + 48dp 热区），而非整行内容。
    expect(otherRect.height - defaultRect.height, lessThan(60));

    // 操作按钮应右对齐贴住卡片内容右缘（含删除按钮的自定义卡片）。
    final actionButtons = find.descendant(
      of: defaultCard,
      matching: find.byType(AppButton),
    );
    expect(actionButtons, findsNothing);
    final customCard = find.ancestor(
      of: find.text('Custom provider'),
      matching: find.byType(AppCard),
    );
    final customButtons = tester
        .widgetList<AppButton>(
          find.descendant(of: customCard, matching: find.byType(AppButton)),
        )
        .toList();
    expect(customButtons.length, 2, reason: '自定义未默认卡片应有设为默认+删除');
    final lastButton = find.byWidget(customButtons.last);
    final customRect = tester.getRect(customCard);
    expect(
        customRect.right - tester.getRect(lastButton).right, lessThan(24 + 16),
        reason: '操作按钮应右对齐（卡片 margin 8 + 内容 padding 16 以内）');

    expect(tester.takeException(), isNull);
  });

  testWidgets('compact list fits 1.3 text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpPage(
      tester,
      providers: [
        provider('off-a', 'Off A', enabled: false, isBuiltin: true),
        provider('on-b', 'On B'),
      ],
      initialPrefs: {'selectedAiService': 'on-b'},
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.text('Off A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StaticAiProviders extends AiProviders {
  _StaticAiProviders(this._providers);

  final List<AiProvider> _providers;

  @override
  List<AiProvider> build() => _providers;
}
