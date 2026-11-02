import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';

class AiChatPage extends ConsumerWidget {
  const AiChatPage({super.key, this.chatBuilder});

  final WidgetBuilder? chatBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chatBuilder(BuildContext context) {
      return this.chatBuilder?.call(context) ?? const AiChatStream();
    }

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).aiChat)),
      body: AppSafeArea(
        top: false,
        child: Padding(
          padding: AppSettingsAiTokens.chatPadding,
          child: AppAsyncValue<List<ChatMessage>>(
            value: ref.watch(aiChatProvider),
            onRetry: () async {
              ref.invalidate(aiChatProvider);
              await ref.read(aiChatProvider.future);
            },
            isEmpty: (messages) => messages.isEmpty,
            emptyBuilder: chatBuilder,
            dataBuilder: (context, messages) => chatBuilder(context),
          ),
        ),
      ),
    );
  }
}
