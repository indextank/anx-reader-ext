import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('chat page shows a loading state while messages initialize',
      (tester) async {
    final pending = Completer<List<ChatMessage>>();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiChatProvider.overrideWith(() => _PendingAiChat(pending))],
        child: AiChatPage(
          chatBuilder: (context) => const Text('chat-body'),
        ),
      ),
    );

    expect(find.byType(AppLoadingIndicator), findsOneWidget);
    expect(find.text('chat-body'), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('chat page retries load failure and preserves empty chat flow',
      (tester) async {
    final notifier = _RetryAiChat();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiChatProvider.overrideWith(() => notifier)],
        child: AiChatPage(
          chatBuilder: (context) => const Text('chat-body'),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pump();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('chat-body'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(notifier.attempts, 2);
    expect(find.text('chat-body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PendingAiChat extends AiChat {
  _PendingAiChat(this.pending);

  final Completer<List<ChatMessage>> pending;

  @override
  Future<List<ChatMessage>> build() => pending.future;
}

class _RetryAiChat extends AiChat {
  var attempts = 0;

  @override
  Future<List<ChatMessage>> build() async {
    attempts++;
    if (attempts == 1) throw StateError('private chat history');
    return [];
  }
}
