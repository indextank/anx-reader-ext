import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().selectedAiService = 'custom';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/anx-real-chat-test',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  testWidgets('send stays pending, failure retries the same content',
      (tester) async {
    final chat = _SendChat();
    await _pumpRealChat(tester, chat: chat);

    final input = find.byType(TextField);
    await tester.enterText(input, 'original message');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(chat.attempts, 1);

    await tester.enterText(input, 'different message');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.attempts, 1);

    final firstStream = chat.firstStream!;
    firstStream.addError(StateError('private stream failure'));
    await firstStream.close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private stream failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(chat.attempts, 2);
    expect(chat.sentMessages, ['original message', 'original message']);
    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal retry restores the pre-send provider context',
      (tester) async {
    final chat = _ContextChat([
      ChatMessage.humanText('earlier question'),
      ChatMessage.ai('earlier answer'),
    ]);
    await _pumpRealChat(tester, chat: chat);

    await tester.enterText(find.byType(TextField), 'original message');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppInlineFeedback), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(chat.attempts, 2);
    expect(chat.contexts, hasLength(2));
    expect(_messageTexts(chat.contexts[0]), _messageTexts(chat.contexts[1]));
    expect(
      _humanTexts(chat.currentMessages),
      ['earlier question', 'original message'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('regenerate retry restores the truncated provider context',
      (tester) async {
    final chat = _ContextChat([
      ChatMessage.humanText('earlier question'),
      ChatMessage.ai('earlier answer'),
      ChatMessage.humanText('question to regenerate'),
      ChatMessage.ai('answer to replace'),
    ]);
    await _pumpRealChat(tester, chat: chat);
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('Regenerate'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.tap(find.text('Regenerate'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppInlineFeedback), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(chat.attempts, 2);
    expect(chat.regenerateFlags, [true, true]);
    expect(chat.contexts, hasLength(2));
    expect(_messageTexts(chat.contexts[0]),
        ['earlier question', 'earlier answer']);
    expect(_messageTexts(chat.contexts[1]),
        ['earlier question', 'earlier answer']);
    expect(
      _humanTexts(chat.currentMessages),
      ['earlier question', 'question to regenerate'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history load failure retries inside the real drawer',
      (tester) async {
    final cachePath = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) => cachePath.future,
    );
    final history = _RetryHistory();
    await _pumpRealChat(tester, chat: _SendChat(), history: history);

    await tester.tap(find.byIcon(Icons.insert_drive_file));
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(history.attempts, 1);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
    cachePath.complete('/tmp/anx-real-chat-test');
    await tester.pumpAndSettle();
  });

  testWidgets('initial chat error is localized and retries loading',
      (tester) async {
    final chat = _InitialFailureChat();
    await _pumpRealChat(tester, chat: chat);
    await tester.pump();

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.textContaining('private initialization failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(chat.attempts, 2);
    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpRealChat(
  WidgetTester tester, {
  required AiChat chat,
  AiHistoryNotifier? history,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiChatProvider.overrideWith(() => chat),
        aiProvidersProvider.overrideWith(_ChatProviders.new),
        aiHistoryProvider.overrideWith(
          (ref) => history ?? _EmptyHistory(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
          eInkMode: false,
        ),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const AiChatStream(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _ChatProviders extends AiProviders {
  @override
  List<AiProvider> build() => [
        AiProvider(
          id: 'custom',
          title: 'Custom',
          url: 'https://example.com/v1',
          protocol: AiProtocol.openai,
          apiKeys: [AiApiKey(id: 'key', key: 'secret')],
          model: 'model-a',
        ),
      ];
}

class _SendChat extends AiChat {
  var attempts = 0;
  final sentMessages = <String>[];
  StreamController<List<ChatMessage>>? firstStream;

  @override
  Future<List<ChatMessage>> build() async => [];

  @override
  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef ref,
    bool isRegenerate,
  ) {
    attempts++;
    sentMessages.add(message);
    if (attempts == 1) {
      firstStream = StreamController<List<ChatMessage>>();
      return firstStream!.stream;
    }
    return Stream.fromIterable([
      [ChatMessage.humanText(message), ChatMessage.ai('recovered')],
    ]);
  }
}

class _InitialFailureChat extends AiChat {
  var attempts = 0;

  @override
  Future<List<ChatMessage>> build() async {
    attempts++;
    if (attempts == 1) throw StateError('private initialization failure');
    return [];
  }
}

class _EmptyHistory extends AiHistoryNotifier {
  _EmptyHistory() {
    state = const AsyncValue.data([]);
  }
}

class _RetryHistory extends AiHistoryNotifier {
  _RetryHistory() {
    state = AsyncValue.error(
      StateError('private history failure'),
      StackTrace.current,
    );
  }

  var attempts = 0;

  @override
  Future<void> refresh() async {
    attempts++;
    state = const AsyncValue.loading();
    state = const AsyncValue.data([]);
  }
}

class _ContextChat extends AiChat {
  _ContextChat(this.initial);

  final List<ChatMessage> initial;
  var attempts = 0;
  final contexts = <List<ChatMessage>>[];
  final regenerateFlags = <bool>[];

  List<ChatMessage> get currentMessages => state.value ?? const [];

  @override
  Future<List<ChatMessage>> build() async => initial;

  @override
  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef ref,
    bool isRegenerate,
  ) async* {
    attempts++;
    regenerateFlags.add(isRegenerate);
    final before = List<ChatMessage>.from(state.value ?? const []);
    contexts.add(before);
    final partial = [
      ...before,
      ChatMessage.humanText(message),
      ChatMessage.ai('partial answer'),
    ];
    state = AsyncValue.data(partial);
    yield partial;
    if (attempts == 1) throw StateError('private partial failure');
    final recovered = [
      ...before,
      ChatMessage.humanText(message),
      ChatMessage.ai('recovered answer'),
    ];
    state = AsyncValue.data(recovered);
    yield recovered;
  }
}

List<String> _messageTexts(List<ChatMessage> messages) {
  return messages.map((message) => message.contentAsString).toList();
}

List<String> _humanTexts(List<ChatMessage> messages) {
  return messages
      .whereType<HumanChatMessage>()
      .map((message) => message.contentAsString)
      .toList();
}
