import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/markdown/selection_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AiMarkdown extends StatelessWidget {
  const AiMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.fontSize,
  });

  final String data;
  final bool selectable;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = GptMarkdown(
      data,
      followLinkColor: true,
      style: fontSize == null ? null : TextStyle(fontSize: fontSize),
      codeBuilder: (context, name, codes, closed) {
        return _AiCodeBlock(language: name, code: codes);
      },
      onLinkTap: (href, text) {
        launchUrlString(href, mode: LaunchMode.externalApplication);
      },
      linkBuilder: (context, text, url, style) => Text.rich(
        text,
        style: style.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
    if (!selectable) return content;
    return SelectableRegion(
      selectionControls: selectionControls(),
      child: content,
    );
  }
}

class _AiCodeBlock extends StatelessWidget {
  const _AiCodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      margin: AppSpacing.zero,
      padding: AppSpacing.zero,
      borderRadius: AppRadius.border8,
      color: theme.colorScheme.onInverseSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppAiTokens.codeHeaderPadding,
            child: Row(
              children: [
                Expanded(child: Text(language)),
                AppIconButton(
                  icon: Icons.content_paste,
                  tooltip: L10n.of(context).commonCopy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      AppFeedback.showInfo(
                        context,
                        message: L10n.of(context).notesPageCopied,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: AppAiTokens.codeDividerHeight),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppAiTokens.codeContentPadding,
            child: Text(
              code,
              style: AppAiTokens.codeTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}
