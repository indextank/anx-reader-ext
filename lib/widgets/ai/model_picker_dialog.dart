import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/ai_model_service.dart';
import 'package:anx_reader/theme/app_ai_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

typedef AiModelFetcher = Future<List<String>> Function({
  required String url,
  required String apiKey,
});

/// A dialog that lets the user either type a model name manually or pick one
/// from the auto-fetched list (OpenAI-compatible `/v1/models` endpoint only).
///
/// Returns the selected/entered model string, or `null` if cancelled.
Future<String?> showModelPickerDialog({
  required BuildContext context,
  required AiProvider provider,
  String? currentModel,
  AiModelFetcher? fetchModels,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ModelPickerDialog(
      provider: provider,
      currentModel: currentModel,
      fetchModels: fetchModels,
    ),
  );
}

class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({
    required this.provider,
    this.currentModel,
    this.fetchModels,
  });

  final AiProvider provider;
  final String? currentModel;
  final AiModelFetcher? fetchModels;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  late TextEditingController _controller;
  List<String>? _fetchedModels;
  bool _isFetching = false;
  String? _fetchError;

  bool get _canFetch =>
      widget.provider.protocol == AiProtocol.openai &&
      widget.provider.hasValidKey &&
      widget.provider.url.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentModel ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
      _fetchError = null;
      _fetchedModels = null;
    });

    try {
      final apiKey = widget.provider.currentApiKey ?? '';
      final models = await (widget.fetchModels ?? fetchAiModels)(
        url: widget.provider.url,
        apiKey: apiKey,
      );
      if (mounted) {
        setState(() {
          _fetchedModels = models;
          _isFetching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isFetching = false;
          _fetchError = L10n.of(context).commonLoadFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AppDialog(
      title: l10n.aiModelSwitchTitle,
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _controller,
                label: l10n.aiModelEnterManually,
                border: const OutlineInputBorder(),
                isDense: true,
                autofocus: !_canFetch,
              ),
              if (_canFetch) ...[
                SizedBox(height: AppSpacing.tokens.s8),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: l10n.settingsAiProviderFetchModels,
                    onPressed: _fetchModels,
                    isLoading: _isFetching,
                    size: AppButtonSize.small,
                  ),
                ),
              ],
              if (_isFetching && _fetchedModels == null)
                const AppSkeleton(
                  child: Column(
                    children: [
                      AppListTile(title: 'Model'),
                      AppListTile(title: 'Model'),
                      AppListTile(title: 'Model'),
                    ],
                  ),
                ),
              if (_fetchError != null)
                Padding(
                  padding: AppAiTokens.feedbackTopPadding,
                  child: AppInlineFeedback(
                    message: _fetchError,
                    onRetry: _fetchModels,
                  ),
                ),
              if (_fetchedModels != null && _fetchedModels!.isEmpty)
                AppEmptyState(
                  title: l10n.settingsAiProviderNoModelsFound,
                  actionLabel: l10n.commonRetry,
                  onAction: _fetchModels,
                ),
              if (_fetchedModels != null && _fetchedModels!.isNotEmpty) ...[
                Padding(
                  padding: AppAiTokens.modelSectionPadding,
                  child: Text(
                    l10n.aiModelOrSelectBelow,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height *
                        AppAiTokens.modelListHeightFactor,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fetchedModels!.length,
                    itemBuilder: (context, index) {
                      final modelId = _fetchedModels![index];
                      final isSelected = _controller.text == modelId;
                      return AppListTile(
                        title: modelId,
                        selected: isSelected,
                        onTap: () {
                          setState(() => _controller.text = modelId);
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.commonConfirm,
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.pop(context, text.isEmpty ? null : text);
          },
        ),
      ],
    );
  }
}
