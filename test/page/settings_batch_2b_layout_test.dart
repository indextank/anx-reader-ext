import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/page/settings_page/developer/vibration_test_page.dart';
import 'package:anx_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:anx_reader/providers/ai_cache_count.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/vibration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('AI settings fits compact 1.3 text scale', (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiCacheCountProvider.overrideWith(_Cache.new)],
        child: const AISettings(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _scrollToEnd(tester, find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider list fits compact 1.3 text scale', (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(_Providers.new)],
        child: const AiProviderListPage(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    expect(find.text('Custom provider'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider editor and key dialog fit compact 1.3 text scale',
      (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: AiProviderDetailPage(providerId: null)),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.ensureVisible(find.text('Add Key').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Key').last);
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byType(AppTextField),
    );
    await tester.enterText(fields.at(1), 'secret');
    await tester.tap(find.text('Confirm').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('developer options fits compact 1.3 text scale', (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      const DeveloperOptionsPage(),
      textScaler: const TextScaler.linear(1.3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vibration actions fit compact 1.3 text scale', (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      VibrationTestPage(loadCapabilities: () async => _capabilities),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat empty flow fits compact 1.3 text scale', (tester) async {
    _useCompactView(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiChatProvider.overrideWith(_EmptyChat.new)],
        child: AiChatPage(
          chatBuilder: (context) => const Text('chat-body'),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pumpAndSettle();
    expect(find.text('chat-body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _useCompactView(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _scrollToEnd(WidgetTester tester, Finder finder) async {
  final scrollable = tester.state<ScrollableState>(finder);
  for (var index = 0; index < 3; index++) {
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _Cache extends AiCacheCount {
  @override
  Future<int> build() async => 0;
}

class _Providers extends AiProviders {
  @override
  List<AiProvider> build() => [
        AiProvider(
          id: 'custom',
          title: 'Custom provider',
          url: 'https://example.com/v1',
          protocol: AiProtocol.openai,
        ),
      ];
}

class _EmptyChat extends AiChat {
  @override
  Future<List<ChatMessage>> build() async => [];
}

const _capabilities = VibrationCapabilities(
  hasVibrator: true,
  hasAmplitudeControl: true,
  hasCustomVibrationsSupport: true,
  canUseHaptics: true,
);
