import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/ai/model_picker_dialog.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:anx_reader/widgets/ai/ai_markdown.dart';
import 'package:anx_reader/widgets/ai/ai_chat_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream({
    super.key,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.trailing,
    this.session,
  });

  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;
  final AiChatSession? session;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  late final AiChatSession _session;
  TextEditingController get inputController => _session.inputController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Stream<List<ChatMessage>>? get _messageStream => _session.messageStream;
  set _messageStream(Stream<List<ChatMessage>>? value) =>
      _session.messageStream = value;
  StreamController<List<ChatMessage>>? get _messageController =>
      _session.messageController;
  set _messageController(StreamController<List<ChatMessage>>? value) =>
      _session.messageController = value;
  StreamSubscription<List<ChatMessage>>? get _messageSubscription =>
      _session.messageSubscription;
  set _messageSubscription(StreamSubscription<List<ChatMessage>>? value) =>
      _session.messageSubscription = value;
  bool get _isStreaming => _session.isStreaming;
  set _isStreaming(bool value) => _session.isStreaming = value;
  String? get _lastSentMessage => _session.lastSentMessage;
  set _lastSentMessage(String? value) => _session.lastSentMessage = value;
  bool get _lastSendWasRegenerate => _session.lastSendWasRegenerate;
  set _lastSendWasRegenerate(bool value) =>
      _session.lastSendWasRegenerate = value;
  List<ChatMessage> get _preSendMessages => _session.preSendMessages;
  set _preSendMessages(List<ChatMessage> value) =>
      _session.preSendMessages = value;
  String? get _preSendSessionId => _session.preSendSessionId;
  set _preSendSessionId(String? value) => _session.preSendSessionId = value;
  final ScrollController _scrollController = ScrollController();
  List<String> _suggestedPrompts = const [];
  List<String> _starterPrompts = const [];
  Locale? _promptsLocale;
  double _fontSize = AppAiTokens.defaultChatFontSize;

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
    return [
      {
        'label': L10n.of(context).aiQuickPromptExplain,
        'prompt': L10n.of(context).aiQuickPromptExplainText,
      },
      {
        'label': L10n.of(context).aiQuickPromptOpinion,
        'prompt': L10n.of(context).aiQuickPromptOpinionText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSummary,
        'prompt': L10n.of(context).aiQuickPromptSummaryText,
      },
      {
        'label': L10n.of(context).aiQuickPromptAnalyze,
        'prompt': L10n.of(context).aiQuickPromptAnalyzeText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSuggest,
        'prompt': L10n.of(context).aiQuickPromptSuggestText,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? AiChatSession();
    _session.addListener(_handleSessionChanged);
    _fontSize = Prefs().aiChatFontSize;
    if (widget.initialMessage != null) {
      inputController.text = widget.initialMessage!;
    }
    if (widget.sendImmediate) {
      _sendMessage();
    }
    _scrollToBottom();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_promptsLocale == locale) return;
    _promptsLocale = locale;
    final l10n = L10n.of(context);
    _starterPrompts = [
      l10n.quickPrompt1,
      l10n.quickPrompt2,
      l10n.quickPrompt3,
      l10n.quickPrompt4,
      l10n.quickPrompt5,
      l10n.quickPrompt6,
      l10n.quickPrompt7,
      l10n.quickPrompt8,
      l10n.quickPrompt9,
      l10n.quickPrompt10,
      l10n.quickPrompt11,
      l10n.quickPrompt12,
    ];
    _suggestedPrompts = _pickSuggestedPrompts();
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChanged);
    if (widget.session == null) _session.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) setState(() {});
  }

  AiProvider? _currentProvider(List<AiProvider> enabledProviders) {
    final selectedId = Prefs().selectedAiService;
    try {
      return enabledProviders.firstWhere((p) => p.id == selectedId);
    } catch (_) {
      return enabledProviders.isNotEmpty ? enabledProviders.first : null;
    }
  }

  String _modelLabel(AiProvider provider) {
    final model = provider.model;
    if (model.trim().isNotEmpty) return model;
    // Fallback: look up default model from built-in templates
    final defaults = buildDefaultAiServices();
    for (final d in defaults) {
      if (d.identifier == provider.id) return d.defaultModel;
    }
    return '';
  }

  void _onProviderSelected(String providerId) {
    if (_isStreaming) return;
    ref.read(aiProvidersProvider.notifier).setSelectedProvider(providerId);
  }

  AiProvider? _providerById(List<AiProvider> providers, String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<String> _pickSuggestedPrompts() {
    final prompts = List<String>.from(_starterPrompts)..shuffle();
    return prompts.take(3).toList(growable: false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppAiTokens.scrollDuration,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    final historyState = ref.watch(aiHistoryProvider);
    return AppSafeArea(
      child: Column(
        children: [
          AppListTile(
            title: L10n.of(context).conversationHistory,
            trailing: AppIconButton(
              icon: Icons.delete_sweep,
              tooltip: L10n.of(context).commonDelete,
              onPressed: _showClearHistoryConfirmation,
            ),
          ),
          Expanded(
            child: AppAsyncValue<List<AiChatHistoryEntry>>(
              value: historyState,
              onRetry: () => ref.read(aiHistoryProvider.notifier).refresh(),
              isEmpty: (items) => items.isEmpty,
              emptyBuilder: (context) => AppEmptyState(
                title: L10n.of(context).noConversationTip,
              ),
              errorBuilder: (context, error, stack) => AppErrorState(
                title: L10n.of(context).failedToLoadHistoryTip,
                onRetry: () => ref.read(aiHistoryProvider.notifier).refresh(),
              ),
              dataBuilder: (context, items) => ListView.separated(
                padding: AppAiTokens.historyListPadding,
                itemCount: items.length,
                separatorBuilder: (_, __) => SizedBox(
                  height: AppAiTokens.historySeparatorHeight,
                ),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  return _buildHistoryTile(context, entry);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, AiChatHistoryEntry entry) {
    final allProviders = ref.watch(aiProvidersProvider);
    final provider = _providerById(allProviders, entry.serviceId);
    final statusColor = entry.completed
        ? context.appTheme.colors.success
        : Theme.of(context).colorScheme.tertiary;
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return AppCard(
      margin: AppAiTokens.historyCardMargin,
      padding: AppAiTokens.historyCardPadding,
      borderRadius: AppAiTokens.historyCardRadius,
      onTap: () => _handleHistoryTap(context, entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _formatTimestamp(entry.updatedAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.circle,
                    size: AppAiTokens.historyStatusSize,
                    color: statusColor,
                  ),
                  AppIconButton(
                    icon: Icons.delete_outline,
                    tooltip: L10n.of(context).commonDelete,
                    onPressed: () => _showDeleteHistoryConfirmation(entry),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildHistorySubtitle(AiProvider? provider, AiChatHistoryEntry entry) {
    final serviceLabel = provider?.title ?? entry.serviceId;
    if (entry.model.isEmpty) {
      return serviceLabel;
    }
    return '$serviceLabel · ${entry.model}';
  }

  Widget? _providerLogo(AiProvider? provider) {
    final logo = provider?.logoAsset;
    if (logo == null || logo.isEmpty) return null;
    return Image.asset(
      logo,
      width: AppAiTokens.providerLogoSize,
      height: AppAiTokens.providerLogoSize,
      errorBuilder: (_, __, ___) => const SizedBox(),
    );
  }

  String _deriveTitle(AiChatHistoryEntry entry) {
    for (final message in entry.messages) {
      if (message is HumanChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    return '$date $time';
  }

  Future<void> _handleHistoryTap(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    if (_isStreaming) {
      _cancelStreaming();
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    final controller = _messageController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _messageController = null;
    if (!context.mounted) return;

    ref.read(aiChatProvider.notifier).loadHistoryEntry(entry);

    setState(() {
      _messageStream = null;
      // reset state when switching service
    });

    Navigator.of(context).pop();
    _scrollToBottom();
  }

  Future<void> _showDeleteHistoryConfirmation(
    AiChatHistoryEntry entry,
  ) async {
    final l10n = L10n.of(context);
    final title = _deriveTitle(entry);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: title,
      isDangerous: true,
      dangerDescription: '${l10n.commonDelete}: $title',
      onConfirm: () => _confirmDeleteHistory(context, entry),
    );
  }

  Future<void> _showClearHistoryConfirmation() async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: l10n.conversationHistory,
      isDangerous: true,
      dangerDescription: '${l10n.commonDelete}: ${l10n.conversationHistory}',
      onConfirm: () => _confirmClearHistory(context),
    );
  }

  Future<void> _confirmDeleteHistory(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    await ref.read(aiHistoryProvider.notifier).remove(entry.id);

    final currentSessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    if (currentSessionId == entry.id) {
      ref.read(aiChatProvider.notifier).clear();
      setState(() {
        _messageStream = null;
        // reset state when conversation changes
      });
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    await ref.read(aiHistoryProvider.notifier).clear();
    ref.read(aiChatProvider.notifier).clear();
    setState(() {
      _messageStream = null;
    });
  }

  void _sendMessage({bool isRegenerate = false, String? retryMessage}) {
    if (_isStreaming) {
      return;
    }

    final message = retryMessage ?? inputController.text.trim();
    if (message.isEmpty) return;
    _lastSentMessage = message;
    _lastSendWasRegenerate = isRegenerate;
    if (retryMessage == null) {
      _preSendMessages = List<ChatMessage>.from(
        ref.read(aiChatProvider).value ?? const [],
      );
      _preSendSessionId = ref.read(aiChatProvider.notifier).currentSessionId;
      inputController.clear();
    }

    final controller = StreamController<List<ChatMessage>>.broadcast();
    final stream = ref.read(aiChatProvider.notifier).sendMessageStream(
          message,
          ref,
          isRegenerate,
        );

    _session.beginStreaming(
      controller,
      stream,
      message: message,
      isRegenerate: isRegenerate,
      previousMessages: retryMessage == null ? _preSendMessages : const [],
      sessionId: retryMessage == null ? _preSendSessionId : null,
      onEvent: _scrollToBottom,
    );
  }

  void _retryLastMessage() {
    final message = _lastSentMessage;
    if (message == null) return;
    ref.read(aiChatProvider.notifier).restore(
          List<ChatMessage>.from(_preSendMessages),
          sessionId: _preSendSessionId,
        );
    _sendMessage(
      retryMessage: message,
      isRegenerate: _lastSendWasRegenerate,
    );
  }

  void _useQuickPrompt(String prompt, {bool sendImmediately = false}) {
    final existing = inputController.text.trim();
    inputController.text = existing.isEmpty ? prompt : '$prompt $existing';
    inputController.selection = TextSelection.collapsed(
      offset: inputController.text.length,
    );
    if (sendImmediately) {
      _sendMessage();
    }
  }

  Future<void> _confirmClearMessage() async {
    if (_isStreaming) return;
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.aiChat,
      message: l10n.conversationHistory,
      isDangerous: true,
      dangerDescription: '${l10n.commonDelete}: ${l10n.aiChat}',
      onConfirm: () async => _clearMessage(),
    );
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      ref.read(aiChatProvider.notifier).clear();
      _messageStream = null;
      _suggestedPrompts = _pickSuggestedPrompts();
    });
  }

  void _regenerateLastMessage() {
    if (_isStreaming) {
      return;
    }
    final messages = ref.read(aiChatProvider).value;
    if (messages == null || messages.isEmpty) {
      return;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        final history = messages.take(i).toList(growable: false);
        ref.read(aiChatProvider.notifier).restore(history);
        setState(() {
          inputController.text = message.contentAsString;
          _sendMessage(isRegenerate: true);
        });
        break;
      }
    }
  }

  void _copyMessageContent(String content) {
    final parsed = parseReasoningContent(content);
    final clipboardText = _buildCopyableText(parsed, content);
    Clipboard.setData(ClipboardData(text: clipboardText));
    AppFeedback.showInfo(
      context,
      message: L10n.of(context).notesPageCopied,
    );
  }

  void _cancelStreaming() {
    if (!_isStreaming) return;
    cancelActiveAiRequest();
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      _isStreaming = false;
      _messageStream = null;
    });
  }

  void _showFontSizeMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 1,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: AppAiTokens.fontMenuPadding,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).aiChatFontSize,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Text(
                        '${_fontSize.round()}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Expanded(
                        child: Slider(
                          value: _fontSize,
                          min: AppAiTokens.minChatFontSize,
                          max: AppAiTokens.maxChatFontSize,
                          divisions: AppAiTokens.chatFontDivisions,
                          onChanged: (value) {
                            setMenuState(() {});
                            setState(() {
                              _fontSize = value;
                            });
                            Prefs().aiChatFontSize = value;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  ChatMessage? _getLastAssistantMessage() {
    final messages = ref.watch(aiChatProvider).asData?.value;
    if (messages == null || messages.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is AIChatMessage) {
        return messages[i];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final quickPrompts = _getQuickPrompts(context);
    final allProviders = ref.watch(aiProvidersProvider);
    final enabledProviders = allProviders.where((p) => p.enabled).toList();
    final currentProvider = _currentProvider(enabledProviders);
    final selectedId = Prefs().selectedAiService;

    final aiService = PopupMenuButton<String>(
      enabled: !_isStreaming,
      onSelected: _onProviderSelected,
      itemBuilder: (context) {
        return enabledProviders.map((provider) {
          final isSelected = provider.id == selectedId;
          final label = _modelLabel(provider);
          final logo = _providerLogo(provider);
          return PopupMenuItem<String>(
            value: provider.id,
            child: Row(
              children: [
                if (logo != null)
                  logo
                else
                  const SizedBox(width: AppAiTokens.providerLogoSize),
                SizedBox(width: AppSpacing.tokens.s8),
                Expanded(
                  child: Text(
                    label.isNotEmpty
                        ? '${provider.title} · $label'
                        : provider.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check,
                    size: AppAiTokens.providerIconSize,
                  ),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_providerLogo(currentProvider) != null)
            _providerLogo(currentProvider)!,
          SizedBox(width: AppAiTokens.providerSpacing),
          Flexible(
            child: Text(
              currentProvider != null
                  ? () {
                      final label = _modelLabel(currentProvider);
                      return label.isNotEmpty
                          ? '${currentProvider.title} · $label'
                          : currentProvider.title;
                    }()
                  : '',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: AppSpacing.tokens.s4),
          const Icon(
            Icons.expand_more,
            size: AppAiTokens.providerIconSize,
          ),
        ],
      ),
    );
    final inputBox = AppCard(
      padding: AppAiTokens.inputPadding,
      borderRadius: AppAiTokens.inputRadius,
      child: AppSafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      spacing: AppSpacing.tokens.s8,
                      children: quickPrompts.map((prompt) {
                        return ActionChip(
                          label: Text(prompt['label']!),
                          onPressed: () => _useQuickPrompt(prompt['prompt']!),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.tokens.s4),
            AppTextField(
              controller: inputController,
              isDense: true,
              hintText: L10n.of(context).aiHintInputPlaceholder,
              border: InputBorder.none,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
            SizedBox(height: AppSpacing.tokens.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: aiService),
                      if (currentProvider != null)
                        AppIconButton(
                          icon: Icons.tune,
                          tooltip: L10n.of(context).aiModelSwitchTitle,
                          onPressed: () async {
                            final selected = await showModelPickerDialog(
                              context: context,
                              provider: currentProvider,
                              currentModel: currentProvider.model,
                            );
                            if (selected != null &&
                                selected != currentProvider.model) {
                              ref
                                  .read(aiProvidersProvider.notifier)
                                  .updateProvider(
                                    currentProvider.copyWith(model: selected),
                                  );
                            }
                          },
                        ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon: _isStreaming ? Icons.stop : Icons.send,
                  tooltip: _isStreaming
                      ? L10n.of(context).commonCancel
                      : L10n.of(context).commonConfirm,
                  onPressed: _isStreaming ? _cancelStreaming : _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Widget buildEmptyState() {
      final theme = Theme.of(context);

      Widget buildQuickChipColumn() {
        if (widget.quickPromptChips.isEmpty) {
          return const SizedBox.shrink();
        }

        final chips = <Widget>[];
        for (var i = 0; i < widget.quickPromptChips.length; i++) {
          final chip = widget.quickPromptChips[i];
          chips.add(
            Padding(
              padding:
                  i == 0 ? AppSpacing.zero : AppAiTokens.quickPromptTopPadding,
              child: GestureDetector(
                onLongPress: () =>
                    _useQuickPrompt(chip.prompt, sendImmediately: true),
                child: ActionChip(
                  avatar: Icon(
                    chip.icon,
                    size: AppAiTokens.quickPromptIconSize,
                  ),
                  label: Text(chip.label),
                  onPressed: () => _useQuickPrompt(chip.prompt),
                ),
              ),
            ),
          );
        }

        return Positioned(
          right: AppAiTokens.quickPromptRight,
          bottom: AppAiTokens.quickPromptBottom,
          child: SizedBox(
            height: MediaQuery.of(context).size.height *
                AppAiTokens.quickPromptHeightFactor,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: chips,
              ),
            ),
          ),
        );
      }

      return Stack(
        children: [
          if (widget.quickPromptChips.isEmpty)
            Center(
              child: SingleChildScrollView(
                padding: AppSpacing.all16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      L10n.of(context).tryAQuickPrompt,
                      style: theme.textTheme.titleMedium,
                    ),
                    SizedBox(height: AppSpacing.tokens.s12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.tokens.s8,
                      runSpacing: AppSpacing.tokens.s8,
                      children: _suggestedPrompts
                          .map(
                            (prompt) => GestureDetector(
                              onLongPress: () => _useQuickPrompt(
                                prompt,
                                sendImmediately: true,
                              ),
                              child: ActionChip(
                                label: Text(prompt),
                                onPressed: () => _useQuickPrompt(prompt),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
          buildQuickChipColumn(),
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.transparent,
      appBar: AppBar(
        title: Text(L10n.of(context).aiChat),
        leading: AppIconButton(
          icon: Icons.insert_drive_file,
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          AppIconButton(
            icon: Icons.edit_document,
            tooltip: L10n.of(context).commonDelete,
            enabled: !_isStreaming,
            onPressed: _confirmClearMessage,
          ),
          Builder(
            builder: (context) => AppIconButton(
              icon: Icons.more_vert,
              tooltip: L10n.of(context).aiChatFontSize,
              onPressed: () => _showFontSizeMenu(context),
            ),
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: EnvVar.isAppStore &&
              Prefs().shouldShowHint(HintKey.aiDataSharingConsent)
          ? _buildDataSharingConsent(context)
          : Column(
              children: [
                Expanded(
                  child: _messageStream != null
                      ? StreamBuilder<List<ChatMessage>>(
                          stream: _messageStream,
                          initialData: _session.latestMessages,
                          builder: (context, snapshot) {
                            if (_session.latestError != null) {
                              return Center(
                                child: AppInlineFeedback(
                                  onRetry: _retryLastMessage,
                                ),
                              );
                            }
                            final messages =
                                _session.latestMessages ?? snapshot.data;
                            if (messages == null) {
                              return AppSkeleton(
                                child: Center(
                                  child: Text(L10n.of(context).commonLoading),
                                ),
                              );
                            }

                            if (messages.isEmpty) {
                              return buildEmptyState();
                            }

                            return _buildMessageList(messages);
                          },
                        )
                      : ref.watch(aiChatProvider).when(
                            data: (messages) {
                              if (messages.isEmpty) {
                                return buildEmptyState();
                              }

                              return _buildMessageList(messages);
                            },
                            loading: () => AppSkeleton(
                              child: Center(
                                child: Text(L10n.of(context).commonLoading),
                              ),
                            ),
                            error: (error, stack) => Center(
                              child: AppInlineFeedback(
                                onRetry: () => ref.invalidate(aiChatProvider),
                              ),
                            ),
                          ),
                ),
                inputBox,
              ],
            ),
    );
  }

  Widget _buildDataSharingConsent(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth =
        MediaQuery.of(context).size.width * AppAiTokens.consentWidthFactor;
    final constrainedWidth = maxWidth > AppAiTokens.consentMaxWidth
        ? AppAiTokens.consentMaxWidth
        : maxWidth;

    return Container(
      color: theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: AppAiTokens.consentPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constrainedWidth),
            child: AppCard(
              padding: AppAiTokens.consentPadding,
              borderRadius: AppAiTokens.consentRadius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: AppAiTokens.consentIconSize,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(height: AppSpacing.tokens.s20),
                  Text(
                    L10n.of(context).aiDataSharingTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: AppSpacing.tokens.s16),
                  Text(
                    L10n.of(context).aiDataSharingContent,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: AppSpacing.tokens.s24),
                  AppButton(
                    label: L10n.of(context).aiDataSharingAgree,
                    onPressed: () {
                      Prefs().setShowHint(HintKey.aiDataSharingConsent, false);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isStreaming =
            _messageStream != null && index == messages.length - 1;
        return _buildMessageItem(message, index, isStreaming);
      },
    );
  }

  Widget _buildMessageItem(
    ChatMessage message,
    int index,
    bool isStreaming,
  ) {
    final isUser = message is HumanChatMessage;
    final content = chatMessageDisplayContent(message);
    final parsed = parseReasoningContent(content);
    final isLongMessage = content.length > AppAiTokens.longMessageThreshold;
    final lastAssistantMessage = _getLastAssistantMessage();

    return Padding(
      padding: AppSpacing.only(
        bottom: AppSpacing.tokens.s8,
        left: isUser ? AppSpacing.tokens.s8 : 0,
        right: isUser ? 0 : AppSpacing.tokens.s8,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: AppSpacing.tokens.s8),
          Flexible(
            child: AppCard(
              padding: AppAiTokens.messagePadding,
              color: isUser
                  ? Theme.of(context).colorScheme.surfaceContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: isUser
                  ? AppAiTokens.messageUserRadius
                  : AppAiTokens.messageAssistantRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? _buildCollapsibleText(content, isLongMessage)
                      : _buildAssistantTimeline(parsed, isStreaming),
                  if (!isUser)
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        if (identical(message, lastAssistantMessage))
                          AppButton(
                            label: L10n.of(context).aiRegenerate,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.small,
                            enabled: !_isStreaming,
                            onPressed: _regenerateLastMessage,
                          ),
                        AppButton(
                          label: L10n.of(context).commonCopy,
                          variant: AppButtonVariant.text,
                          size: AppButtonSize.small,
                          onPressed: () => _copyMessageContent(content),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: AppSpacing.tokens.s8),
        ],
      ),
    );
  }

  String _buildCopyableText(ParsedReasoning parsed, String fallback) {
    final buffer = StringBuffer();
    var hasWrittenSection = false;

    void startSection() {
      if (hasWrittenSection) {
        buffer.writeln();
      } else {
        hasWrittenSection = true;
      }
    }

    // void appendField(String label, String? value) {
    //   final trimmed = value?.trim();
    //   if (trimmed != null && trimmed.isNotEmpty) {
    //     buffer.writeln('$label: $trimmed');
    //   }
    // }

    for (final entry in parsed.timeline) {
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          final text = entry.text?.trim();
          if (text != null && text.isNotEmpty) {
            startSection();
            buffer.writeln(text);
          }
          break;
        case ParsedReasoningEntryType.tool:
          // final step = entry.toolStep;
          // if (step != null) {
          //   startSection();
          //   buffer.writeln('[${step.name} (${step.status})]');
          //   appendField('Input', step.input);
          //   appendField('Output', step.output);
          //   appendField('Error', step.error);
          // }
          break;
      }
    }

    final copyText = buffer.toString().trimRight();
    if (copyText.isEmpty) {
      return fallback;
    }
    return copyText;
  }

  Widget _buildAssistantTimeline(ParsedReasoning parsed, bool isStreaming) {
    if (parsed.timeline.isEmpty) {
      return isStreaming
          ? AppSkeleton(child: Text(L10n.of(context).aiReasoningThinking))
          : const SizedBox.shrink();
    }

    final reasoningWidgets = _buildTimelineWidgets(
      parsed.reasoningTimeline,
      fontSize: (_fontSize - AppAiTokens.reasoningFontDelta)
          .clamp(AppAiTokens.minReasoningFontSize, _fontSize)
          .toDouble(),
    );
    final answerWidgets = _buildTimelineWidgets(
      parsed.answerTimeline,
      fontSize: _fontSize,
    );
    final widgets = <Widget>[];

    if (reasoningWidgets.isNotEmpty) {
      widgets.add(_buildThinkingPanel(reasoningWidgets));
    }
    if (answerWidgets.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: AppSpacing.tokens.s8));
      }
      widgets.addAll(answerWidgets);
    } else if (widgets.isEmpty && isStreaming) {
      widgets
          .add(AppSkeleton(child: Text(L10n.of(context).aiReasoningThinking)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _buildTimelineWidgets(
    List<ParsedReasoningEntry> timeline, {
    required double fontSize,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < timeline.length; i++) {
      final entry = timeline[i];
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          if (entry.text != null && entry.text!.trim().isNotEmpty) {
            widgets.add(
              AiMarkdown(
                data: entry.text!,
                selectable: true,
                fontSize: fontSize,
              ),
            );
          }
          break;
        case ParsedReasoningEntryType.tool:
          if (entry.toolStep != null) {
            widgets.add(_buildToolTile(entry.toolStep!));
          }
          break;
      }

      if (i != timeline.length - 1) {
        widgets.add(SizedBox(height: AppSpacing.tokens.s8));
      }
    }
    return widgets;
  }

  Widget _buildThinkingPanel(List<Widget> children) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.secondary.withValues(
      alpha: AppAiTokens.thinkingAccentAlpha,
    );
    final subtleColor = theme.colorScheme.secondary.withValues(
      alpha: AppAiTokens.thinkingSubtleAlpha,
    );
    return Theme(
      data: theme.copyWith(dividerColor: AppColors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: AppSpacing.zero,
        childrenPadding: AppAiTokens.thinkingPadding,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: subtleColor,
        collapsedIconColor: subtleColor,
        leading: Icon(
          Icons.psychology_alt_outlined,
          size: AppAiTokens.thinkingIconSize,
          color: accentColor,
        ),
        title: Text(
          L10n.of(context).aiThinkingHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: accentColor,
            fontSize: AppAiTokens.thinkingTitleFontSize,
          ),
        ),
        children: [
          Container(
            margin: AppAiTokens.thinkingMargin,
            padding: AppAiTokens.thinkingContentPadding,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: subtleColor.withValues(
                    alpha: AppAiTokens.thinkingBorderAlpha,
                  ),
                  width: AppAiTokens.thinkingBorderWidth,
                ),
              ),
            ),
            child: Opacity(
              opacity: AppAiTokens.thinkingOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTile(ParsedToolStep step) {
    if (step.name == 'bookshelf_organize') {
      return OrganizeBookshelfStepTile(step: step);
    }
    if (step.name == 'mindmap_draw') {
      return MindmapStepTile(step: step);
    }
    if (step.name == 'apply_book_tags') {
      return ApplyBookTagsStepTile(step: step);
    }
    return ToolStepTile(step: step);
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    if (!isLongMessage) {
      return SelectableText(
        text,
        style: TextStyle(fontSize: _fontSize),
        selectionControls: MaterialTextSelectionControls(),
      );
    }

    return _CollapsibleText(text: text, fontSize: _fontSize);
  }
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({
    required this.text,
    this.fontSize = AppAiTokens.defaultChatFontSize,
  });

  final String text;
  final double fontSize;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isExpanded)
          SelectableText(
            widget.text,
            style: TextStyle(fontSize: widget.fontSize),
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, AppAiTokens.collapsedPreviewLength),
                style: TextStyle(fontSize: widget.fontSize),
                selectionControls: MaterialTextSelectionControls(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: AppAiTokens.collapsedFadeHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.surfaceContainer,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        AppButton(
          label: _isExpanded
              ? L10n.of(context).aiHintCollapse
              : L10n.of(context).aiHintExpand,
          variant: AppButtonVariant.text,
          size: AppButtonSize.small,
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
        ),
      ],
    );
  }
}
