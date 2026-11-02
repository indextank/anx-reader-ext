import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_cache_count.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('AI cache load failure has a visible retry state',
      (tester) async {
    final notifier = _FailingAiCacheCount();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiCacheCountProvider.overrideWith(() => notifier)],
        child: const AISettings(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await _scrollAiSettingsToEnd(tester);
    expect(find.text('AI Cache'), findsOneWidget);
    final cacheValue = tester.widget<AppAsyncValue<int>>(
      find.byType(AppAsyncValue<int>),
    );
    expect(cacheValue.value.hasError, isTrue);
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('AI cache clear deduplicates and recovers in the dialog',
      (tester) async {
    final firstAttempt = Completer<void>();
    var attempts = 0;
    final notifier = _ClearAiCacheCount(() {
      attempts++;
      if (attempts == 1) return firstAttempt.future;
      return Future.value();
    });
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiCacheCountProvider.overrideWith(() => notifier)],
        child: const AISettings(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _scrollAiSettingsToEnd(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);

    await tester.tap(_dialogText('Delete'));
    await tester.pump();
    await tester.tap(_dialogText('Delete'));
    await tester.pump();
    expect(attempts, 1);

    firstAttempt.completeError(StateError('private clear failure'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);

    await tester.tap(_dialogText('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider list has an empty state with an add action',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(_EmptyAiProviders.new)],
        child: const AiProviderListPage(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Add Provider'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new provider shows an accessible empty API key state',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: AiProviderDetailPage(providerId: null)),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No valid API keys configured'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model fetch deduplicates pending and presents an empty result',
      (tester) async {
    final pending = Completer<List<String>>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: AiProviderDetailPage(
          providerId: null,
          fetchModels: ({required url, required apiKey}) {
            attempts++;
            return pending.future;
          },
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _addApiKey(tester);
    await tester.enterText(
      find.byType(AppTextField).at(1),
      'https://example.com/v1',
    );

    await tester.tap(find.text('Fetch Models'));
    await tester.pump();
    await tester.tap(find.text('Fetch Models'), warnIfMissed: false);
    await tester.pump();
    expect(attempts, 1);

    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No models found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model fetch failure is understandable and retries to data',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: AiProviderDetailPage(
          providerId: null,
          fetchModels: ({required url, required apiKey}) async {
            attempts++;
            if (attempts == 1) throw StateError('secret response body');
            return ['model-a'];
          },
        ),
      ),
    );
    await _addApiKey(tester);
    await tester.enterText(
      find.byType(AppTextField).at(1),
      'https://example.com/v1',
    );

    await tester.tap(find.text('Fetch Models'));
    await tester.pumpAndSettle();
    expect(find.text("Content couldn't be loaded. Try again."), findsOneWidget);
    expect(find.textContaining('secret response body'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('model-a'), findsOneWidget);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection test deduplicates an in-flight submission',
      (tester) async {
    final pending = Completer<void>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(_SingleAiProviders.new)],
        child: AiProviderDetailPage(
          providerId: 'custom',
          testConnection: () {
            attempts++;
            return pending.future;
          },
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.ensureVisible(find.text('Test Connection'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    await tester.tap(find.text('Test Connection'));
    await tester.pump();

    expect(attempts, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection test failure offers a working retry', (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(_SingleAiProviders.new)],
        child: AiProviderDetailPage(
          providerId: 'custom',
          testConnection: () async {
            attempts++;
            if (attempts == 1) throw StateError('private connection error');
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Test Connection'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test Connection'));
    await tester.pumpAndSettle();
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private connection error'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom provider deletion honors cancel and confirm',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(_SingleAiProviders.new)],
        child: const AiProviderListPage(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsNothing);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in prompt reset and save keep preference behavior',
      (tester) async {
    Prefs().saveAiPrompt(AiPrompts.test, 'custom-prompt');
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: AISettings()),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.ensureVisible(find.text('Test AI config'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test AI config'));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byType(AppTextField),
    );
    expect(
        tester.widget<AppTextField>(field).controller?.text, 'custom-prompt');
    await tester.tap(_dialogText('Reset'));
    await tester.pump();
    final defaultPrompt = Prefs().getAiPrompt(AiPrompts.test);
    expect(tester.widget<AppTextField>(field).controller?.text, defaultPrompt);

    await tester.enterText(field, 'updated-prompt');
    await tester.tap(_dialogText('Save'));
    await tester.pumpAndSettle();
    expect(Prefs().getAiPrompt(AiPrompts.test), 'updated-prompt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('API key deletion honors cancel and confirm', (tester) async {
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: AiProviderDetailPage(providerId: null)),
      textScaler: const TextScaler.linear(1.3),
    );
    await _addApiKey(tester);
    await tester.ensureVisible(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('API Key 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('API Key 1'), findsNothing);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new provider save preserves form data and deduplicates',
      (tester) async {
    final notifier = _RecordingAiProviders([]);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(() => notifier)],
        child: const AiProviderDetailPage(providerId: null),
      ),
    );
    await tester.enterText(find.byType(AppTextField).at(0), 'New provider');
    await tester.enterText(
      find.byType(AppTextField).at(1),
      'https://new.example.com/v1',
    );
    await tester.enterText(find.byType(AppTextField).at(2), 'model-new');
    await _addApiKey(tester);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump();

    expect(notifier.addCalls, 1);
    expect(notifier.updateCalls, 0);
    final saved = notifier.saved!;
    expect(saved.title, 'New provider');
    expect(saved.url, 'https://new.example.com/v1');
    expect(saved.model, 'model-new');
    expect(saved.apiKeys.single.key, 'test-key');
    expect(saved.enabled, isTrue);
    expect(saved.isBuiltin, isFalse);
    expect(saved.keyIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider update preserves existing metadata and deduplicates',
      (tester) async {
    final createdAt = DateTime.utc(2020);
    final existing = AiProvider(
      id: 'custom',
      title: 'Before',
      logoAsset: 'assets/icon/openai.png',
      url: 'https://example.com/v1',
      protocol: AiProtocol.openai,
      enabled: false,
      isBuiltin: true,
      apiKeys: [AiApiKey(id: 'key', key: 'secret')],
      model: 'model-a',
      keyIndex: 3,
      createdAt: createdAt,
    );
    final notifier = _RecordingAiProviders([existing]);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiProvidersProvider.overrideWith(() => notifier)],
        child: const AiProviderDetailPage(providerId: 'custom'),
      ),
    );
    await tester.enterText(find.byType(AppTextField).at(0), 'After');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump();

    expect(notifier.updateCalls, 1);
    expect(notifier.addCalls, 0);
    final saved = notifier.saved!;
    expect(saved.title, 'After');
    expect(saved.logoAsset, existing.logoAsset);
    expect(saved.enabled, isFalse);
    expect(saved.isBuiltin, isTrue);
    expect(saved.keyIndex, 3);
    expect(saved.createdAt, createdAt);
    expect(saved.apiKeys, existing.apiKeys);
    expect(saved.model, 'model-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('user prompt deletion honors cancel and confirm', (tester) async {
    final now = DateTime.now();
    Prefs().userPrompts = [
      UserPrompt(
        id: 'prompt',
        name: 'Delete me',
        content: 'Prompt body',
        order: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await pumpDesignSystem(
      tester,
      const ProviderScope(child: AISettings()),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.dragUntilVisible(
      find.text('Delete me'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().userPrompts, hasLength(1));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(Prefs().userPrompts, isEmpty);
    expect(find.text('Delete me'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollAiSettingsToEnd(WidgetTester tester) async {
  await tester.pump();
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  for (var index = 0; index < 2; index++) {
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _addApiKey(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Add Key').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add Key').last);
  await tester.pumpAndSettle();
  final dialog = find.byType(AppDialog);
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(AppTextField)).at(1),
    'test-key',
  );
  await tester.tap(_dialogText('Confirm'));
  await tester.pumpAndSettle();
}

Finder _dialogText(String text) {
  return find
      .descendant(of: find.byType(AppDialog), matching: find.text(text))
      .last;
}

class _FailingAiCacheCount extends AiCacheCount {
  @override
  Future<int> build() async => throw StateError('private cache details');
}

class _ClearAiCacheCount extends AiCacheCount {
  _ClearAiCacheCount(this.onClear);

  final Future<void> Function() onClear;

  @override
  Future<int> build() async => 3;

  @override
  Future<void> clearCache() => onClear();
}

class _EmptyAiProviders extends AiProviders {
  @override
  List<AiProvider> build() => [];
}

class _SingleAiProviders extends AiProviders {
  @override
  List<AiProvider> build() => [
        AiProvider(
          id: 'custom',
          title: 'Custom',
          url: 'https://example.com/v1',
          protocol: AiProtocol.openai,
          apiKeys: [
            AiApiKey(id: 'key', key: 'secret', enabled: true),
          ],
          model: 'model-a',
        ),
      ];
}

class _RecordingAiProviders extends AiProviders {
  _RecordingAiProviders(this.initial);

  final List<AiProvider> initial;
  var addCalls = 0;
  var updateCalls = 0;
  AiProvider? saved;

  @override
  List<AiProvider> build() => initial;

  @override
  void addProvider(AiProvider provider) {
    addCalls++;
    saved = provider;
    state = [...state, provider];
  }

  @override
  void updateProvider(AiProvider provider) {
    updateCalls++;
    saved = provider;
    state = [
      for (final item in state)
        if (item.id == provider.id) provider else item,
    ];
  }
}
