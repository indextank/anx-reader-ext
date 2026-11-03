import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:langchain_core/chat_models.dart';

/// Owns chat input and an in-flight response independently of popup/split UI.
class AiChatSession extends ChangeNotifier {
  final TextEditingController inputController = TextEditingController();
  Stream<List<ChatMessage>>? messageStream;
  StreamController<List<ChatMessage>>? messageController;
  StreamSubscription<List<ChatMessage>>? messageSubscription;
  List<ChatMessage>? latestMessages;
  bool isStreaming = false;
  String? lastSentMessage;
  bool lastSendWasRegenerate = false;
  List<ChatMessage> preSendMessages = const [];
  String? preSendSessionId;

  void beginStreaming(
    StreamController<List<ChatMessage>> controller,
    Stream<List<ChatMessage>> source, {
    required String message,
    required bool isRegenerate,
    required List<ChatMessage> previousMessages,
    required String? sessionId,
    required VoidCallback onEvent,
  }) {
    cancelSubscription();
    messageController?.close();
    lastSentMessage = message;
    lastSendWasRegenerate = isRegenerate;
    if (previousMessages.isNotEmpty || sessionId != null) {
      preSendMessages = previousMessages;
      preSendSessionId = sessionId;
    }
    messageController = controller;
    messageStream = controller.stream;
    isStreaming = true;
    notifyListeners();
    messageSubscription = source.listen(
      (event) {
        latestMessages = event;
        if (!controller.isClosed) controller.add(event);
        onEvent();
      },
      onError: (error, stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
          controller.close();
        }
        isStreaming = false;
        notifyListeners();
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
        isStreaming = false;
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  void cancelSubscription() {
    messageSubscription?.cancel();
    messageSubscription = null;
  }

  void clearStream() {
    cancelSubscription();
    messageController?.close();
    messageController = null;
    messageStream = null;
    latestMessages = null;
    isStreaming = false;
  }

  @override
  void dispose() {
    clearStream();
    inputController.dispose();
    super.dispose();
  }
}
