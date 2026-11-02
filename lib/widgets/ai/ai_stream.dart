import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:anx_reader/widgets/ai/ai_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AiStreamFactory = Stream<String> Function(bool regenerate);

class AiStream extends ConsumerStatefulWidget {
  const AiStream({
    super.key,
    required this.prompt,
    this.identifier,
    this.config,
    this.canCopy = true,
    this.regenerate = false,
    this.useAgent = false,
    this.streamFactory,
  });

  final PromptTemplatePayload prompt;
  final String? identifier;
  final Map<String, String>? config;
  final bool canCopy;
  final bool regenerate;
  final bool useAgent;
  final AiStreamFactory? streamFactory;

  @override
  AiStreamState createState() => AiStreamState();
}

class AiStreamState extends ConsumerState<AiStream> {
  late Stream<String> stream;

  @override
  void initState() {
    super.initState();
    stream = _createStream(widget.regenerate);
  }

  Stream<String> _createStream(bool regenerate) {
    final streamFactory = widget.streamFactory;
    if (streamFactory != null) return streamFactory(regenerate);
    final messages = widget.prompt.buildMessages();
    return aiGenerateStream(
      messages,
      identifier: widget.identifier,
      config: widget.config,
      regenerate: regenerate,
      useAgent: widget.useAgent,
      ref: ref,
    );
  }

  Future<void> _retryStream() async {
    setState(() {
      stream = _createStream(widget.regenerate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return StreamBuilder<String>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            message: l10n.commonLoadFailed,
            onRetry: _retryStream,
          );
        }

        if (!snapshot.hasData) {
          return AppSkeleton(
            child: SizedBox(
              width: AppAiTokens.streamLoadingWidth,
              height: AppAiTokens.streamLoadingHeight,
              child: Center(child: Text(l10n.commonLoading)),
            ),
          );
        }

        final data = snapshot.data!;
        final parsed = parseReasoningContent(data);
        final answerWidgets = _buildTimeline(parsed.answerTimeline);
        final reasoningWidgets = _buildTimeline(
          parsed.reasoningTimeline,
          fontSize: AppAiTokens.reasoningFontSize,
        );
        final isCompleted = snapshot.connectionState == ConnectionState.done;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reasoningWidgets.isNotEmpty)
                _buildThinkingPanel(reasoningWidgets),
              if (reasoningWidgets.isNotEmpty && answerWidgets.isNotEmpty)
                SizedBox(height: AppSpacing.tokens.s8),
              if (answerWidgets.isNotEmpty)
                ...answerWidgets
              else if (!isCompleted)
                AppSkeleton(child: Text(l10n.aiReasoningThinking))
              else
                AppEmptyState(title: l10n.commonEmpty, compact: true),
              if (widget.canCopy)
                Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    AppButton(
                      label: l10n.aiRegenerate,
                      variant: AppButtonVariant.text,
                      enabled: isCompleted,
                      onPressed: () {
                        setState(() {
                          stream = _createStream(true);
                        });
                      },
                    ),
                    AppButton(
                      label: l10n.commonCopy,
                      variant: AppButtonVariant.text,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: data));
                        AppFeedback.showInfo(
                          context,
                          message: l10n.notesPageCopied,
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTimeline(
    List<ParsedReasoningEntry> timeline, {
    double? fontSize,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < timeline.length; i++) {
      final entry = timeline[i];
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          if (entry.text != null && entry.text!.trim().isNotEmpty) {
            widgets.add(
              Padding(
                padding: AppAiTokens.toolCardBottomMargin,
                child: AiMarkdown(
                  data: entry.text!,
                  selectable: true,
                  fontSize: fontSize,
                ),
              ),
            );
          }
          break;
        case ParsedReasoningEntryType.tool:
          if (entry.toolStep != null) {
            widgets.add(
              Padding(
                padding: AppAiTokens.toolCardBottomMargin,
                child: _buildToolTile(entry.toolStep!),
              ),
            );
          }
          break;
      }
      if (i != timeline.length - 1) {
        widgets.add(SizedBox(height: AppSpacing.tokens.s4));
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
                  width: AppAiTokens.mindmapEdgeWidth,
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
}
