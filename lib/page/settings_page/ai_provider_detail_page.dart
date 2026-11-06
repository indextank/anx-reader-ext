import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_model_service.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

typedef AiModelsFetcher = Future<List<String>> Function({
  required String url,
  required String apiKey,
});

class AiProviderDetailPage extends ConsumerStatefulWidget {
  final String? providerId;

  const AiProviderDetailPage({
    super.key,
    required this.providerId,
    this.fetchModels,
    this.testConnection,
  });

  final AiModelsFetcher? fetchModels;
  final Future<void> Function()? testConnection;

  @override
  ConsumerState<AiProviderDetailPage> createState() =>
      _AiProviderDetailPageState();
}

class _AiProviderDetailPageState extends ConsumerState<AiProviderDetailPage> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _modelController;

  AiProtocol _selectedProtocol = AiProtocol.openai;
  AiReasoningEffort _reasoningEffort = AiReasoningEffort.auto;
  List<AiApiKey> _apiKeys = [];
  bool _isModified = false;
  bool _isFetchingModels = false;

  @override
  void initState() {
    super.initState();

    final provider = widget.providerId != null
        ? ref
            .read(aiProvidersProvider)
            .firstWhere((p) => p.id == widget.providerId)
        : null;

    _nameController = TextEditingController(text: provider?.title ?? '');
    _urlController = TextEditingController(text: provider?.url ?? '');
    _modelController = TextEditingController(text: provider?.model ?? '');
    _selectedProtocol = provider?.protocol ?? AiProtocol.openai;
    _reasoningEffort = provider?.reasoningEffort ?? AiReasoningEffort.auto;
    _apiKeys = provider?.apiKeys.toList() ?? [];

    _nameController.addListener(() => setState(() => _isModified = true));
    _urlController.addListener(() => setState(() => _isModified = true));
    _modelController.addListener(() => setState(() => _isModified = true));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final provider = widget.providerId != null
        ? ref
            .watch(aiProvidersProvider)
            .firstWhere((p) => p.id == widget.providerId)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.providerId == null
              ? l10n.settingsAiProvidersAdd
              : l10n.settingsAiProviderName,
        ),
        actions: [
          if (_isModified)
            AppSubmitButton(
              label: l10n.commonSave,
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              errorMessage: l10n.commonActionFailed,
              onSubmit: _saveProvider,
            ),
        ],
      ),
      body: AppSafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: AppSettingsAiTokens.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _nameController,
                label: l10n.settingsAiProviderName,
              ),
              SizedBox(height: AppSpacing.tokens.s16),
              Text(
                l10n.settingsAiProviderProtocol,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: AppSpacing.tokens.s8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AnxSegmentedButton<AiProtocol>(
                  selected: {_selectedProtocol},
                  segments: [
                    SegmentButtonItem(
                      value: AiProtocol.openai,
                      label: l10n.settingsAiProviderProtocolOpenai,
                    ),
                    SegmentButtonItem(
                      value: AiProtocol.claude,
                      label: l10n.settingsAiProviderProtocolClaude,
                    ),
                    SegmentButtonItem(
                      value: AiProtocol.gemini,
                      label: l10n.settingsAiProviderProtocolGemini,
                    ),
                  ],
                  onSelectionChanged: (Set<AiProtocol> selection) {
                    setState(() {
                      _selectedProtocol = selection.first;
                      _isModified = true;
                    });
                  },
                ),
              ),
              SizedBox(height: AppSpacing.tokens.s16),
              AppTextField(
                controller: _urlController,
                label: l10n.settingsAiProviderUrl,
                helperText: _selectedProtocol == AiProtocol.openai
                    ? l10n.settingsAiProviderUrlHint
                    : null,
              ),
              SizedBox(height: AppSpacing.tokens.s16),
              AppTextField(
                controller: _modelController,
                label: l10n.settingsAiProviderModel,
              ),
              if (_selectedProtocol == AiProtocol.openai) ...[
                SizedBox(height: AppSpacing.tokens.s8),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: l10n.settingsAiProviderFetchModels,
                    isLoading: _isFetchingModels,
                    onPressed: _fetchModels,
                  ),
                ),
              ],
              SizedBox(height: AppSpacing.tokens.s24),
              _buildAdvancedSettingsCard(context),
              SizedBox(height: AppSpacing.tokens.s16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsAiProviderApiKeys,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.add,
                    onPressed: _addApiKey,
                    tooltip: l10n.settingsAiProviderAddKey,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.tokens.s8),
              if (_apiKeys.isEmpty)
                AppEmptyState(
                  title: l10n.settingsAiProviderNoValidKeys,
                  icon: Icons.key_off_outlined,
                  actionLabel: l10n.settingsAiProviderAddKey,
                  onAction: _addApiKey,
                )
              else
                ..._apiKeys.asMap().entries.map((entry) {
                  return _buildApiKeyTile(entry.value, entry.key);
                }),
              SizedBox(height: AppSpacing.tokens.s24),
              if (provider != null)
                SizedBox(
                  width: double.infinity,
                  child: AppSubmitButton(
                    label: l10n.settingsAiProviderTestConnection,
                    variant: AppButtonVariant.outlined,
                    errorMessage: l10n.commonActionFailed,
                    onSubmit: _testConnection,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedSettingsCard(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.secondary;
    return AppCard(
      padding: AppSpacing.zero,
      child: ExpansionTile(
        tilePadding: AppSettingsAiTokens.advancedTilePadding,
        childrenPadding: AppSpacing.all16,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: accent,
        collapsedIconColor: accent.withValues(alpha: 0.82),
        title: Row(
          children: [
            Container(
              width: AppSettingsAiTokens.advancedIconContainerSize,
              height: AppSettingsAiTokens.advancedIconContainerSize,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: AppRadius.border12,
              ),
              child: Icon(
                Icons.tune_rounded,
                size: AppSettingsAiTokens.segmentedIconSize,
                color: accent,
              ),
            ),
            SizedBox(width: AppSpacing.tokens.s12),
            Expanded(
              child: Text(
                l10n.settingsAdvanced,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        children: [
          AppDropdownField<AiReasoningEffort>(
            value: _reasoningEffort,
            expandedInsets: EdgeInsets.zero,
            label: l10n.settingsAiProviderReasoningEffort,
            items: [
              AppDropdownItem<AiReasoningEffort>(
                value: AiReasoningEffort.auto,
                label: l10n.settingsAiProviderReasoningEffortAuto,
              ),
              AppDropdownItem<AiReasoningEffort>(
                value: AiReasoningEffort.low,
                label: l10n.settingsAiProviderReasoningEffortLow,
              ),
              AppDropdownItem<AiReasoningEffort>(
                value: AiReasoningEffort.medium,
                label: l10n.settingsAiProviderReasoningEffortMedium,
              ),
              AppDropdownItem<AiReasoningEffort>(
                value: AiReasoningEffort.high,
                label: l10n.settingsAiProviderReasoningEffortHigh,
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _reasoningEffort = value;
                _isModified = true;
              });
            },
          ),
          SizedBox(height: AppSpacing.tokens.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: AppSpacing.tokens.s16,
                color: colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Text(
                  l10n.settingsAiProviderReasoningEffortHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeyTile(AiApiKey apiKey, int index) {
    final l10n = L10n.of(context);
    var obscureKey = true;

    return AppCard(
      margin: AppSettingsAiTokens.apiKeyMargin,
      padding: AppSpacing.all12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  apiKey.label?.isNotEmpty == true
                      ? apiKey.label!
                      : 'API Key ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Switch(
                value: apiKey.enabled,
                onChanged: (value) {
                  setState(() {
                    _apiKeys[index] = apiKey.copyWith(enabled: value);
                    _isModified = true;
                  });
                },
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                onPressed: () => _deleteApiKey(index),
                tooltip: l10n.commonDelete,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.tokens.s8),
          StatefulBuilder(
            builder: (context, setFieldState) {
              return AppTextField(
                initialValue: apiKey.key,
                obscureText: obscureKey,
                suffixIcon: AppIconButton(
                  icon: obscureKey ? Icons.visibility_off : Icons.visibility,
                  tooltip: obscureKey ? l10n.showPassword : l10n.hidePassword,
                  onPressed: () {
                    setFieldState(() => obscureKey = !obscureKey);
                  },
                ),
                onChanged: (value) {
                  _apiKeys[index] = apiKey.copyWith(key: value);
                  _isModified = true;
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addApiKey() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddApiKeyDialog(
        onAdd: (label, key) {
          setState(() {
            _apiKeys.add(
              AiApiKey(
                id: const Uuid().v4(),
                key: key,
                enabled: true,
                label: label.isEmpty ? null : label,
                createdAt: DateTime.now(),
              ),
            );
            _isModified = true;
          });
        },
      ),
    );
  }

  Future<void> _deleteApiKey(int index) async {
    final l10n = L10n.of(context);
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: l10n.commonDelete,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.settingsAiProviderDeleteConfirm,
      onConfirm: () async {
        if (!mounted) return;
        setState(() {
          _apiKeys.removeAt(index);
          _isModified = true;
        });
      },
    );
    if (!confirmed || !mounted) return;
    setState(() {});
  }

  Future<void> _fetchModels() async {
    final l10n = L10n.of(context);
    final enabledKeys = _apiKeys.where((k) => k.enabled && k.key.isNotEmpty);
    if (enabledKeys.isEmpty || _urlController.text.trim().isEmpty) {
      AppFeedback.showError(
        context,
        message: l10n.settingsAiProviderNoValidKeys,
      );
      return;
    }

    if (_isFetchingModels) return;
    setState(() => _isFetchingModels = true);
    try {
      final models = await (widget.fetchModels ?? fetchAiModels)(
        url: _urlController.text.trim(),
        apiKey: enabledKeys.first.key,
      );
      if (!mounted) return;
      setState(() => _isFetchingModels = false);
      await _showModelPicker(models);
    } catch (_) {
      if (mounted) {
        AppFeedback.showError(
          context,
          message: l10n.commonLoadFailed,
          onRetry: _fetchModels,
        );
      }
    } finally {
      if (mounted && _isFetchingModels) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  Future<void> _showModelPicker(List<String> models) async {
    final l10n = L10n.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.settingsAiProviderSelectModel,
        content: SizedBox(
          width: double.maxFinite,
          height: AppSettingsAiTokens.modelPickerHeight,
          child: models.isEmpty
              ? AppEmptyState(title: l10n.settingsAiProviderNoModelsFound)
              : ListView.builder(
                  itemCount: models.length,
                  itemBuilder: (context, index) => AppListTile(
                    title: models[index],
                    onTap: () => Navigator.pop(dialogContext, models[index]),
                  ),
                ),
        ),
        actions: [
          AppButton(
            label: l10n.commonCancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _modelController.text = selected;
    setState(() => _isModified = true);
  }

  Future<void> _saveProvider() async {
    final l10n = L10n.of(context);

    if (_nameController.text.isEmpty || _urlController.text.isEmpty) {
      AppFeedback.showError(context, message: l10n.commonFailed);
      return;
    }

    final provider = _buildProvider();
    if (widget.providerId == null) {
      ref.read(aiProvidersProvider.notifier).addProvider(provider);
    } else {
      ref.read(aiProvidersProvider.notifier).updateProvider(provider);
    }

    setState(() => _isModified = false);
    Navigator.pop(context);
  }

  AiProvider _buildProvider() {
    final existing = widget.providerId == null
        ? null
        : ref
            .read(aiProvidersProvider)
            .firstWhere((p) => p.id == widget.providerId);
    return AiProvider(
      id: widget.providerId ?? const Uuid().v4(),
      title: _nameController.text,
      logoAsset: existing?.logoAsset,
      url: _urlController.text,
      protocol: _selectedProtocol,
      enabled: existing?.enabled ?? true,
      isBuiltin: existing?.isBuiltin ?? false,
      apiKeys: _apiKeys,
      model: _modelController.text,
      reasoningEffort: _reasoningEffort,
      keyIndex: existing?.keyIndex ?? 0,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _testConnection() async {
    final l10n = L10n.of(context);
    final enabledKeys = _apiKeys.where(
      (k) => k.enabled && k.key.trim().isNotEmpty,
    );
    if (_urlController.text.trim().isEmpty ||
        _modelController.text.trim().isEmpty ||
        enabledKeys.isEmpty) {
      AppFeedback.showError(
        context,
        message: l10n.settingsAiProviderNoValidKeys,
      );
      return;
    }

    if (_isModified) {
      if (_nameController.text.isEmpty || _urlController.text.isEmpty) {
        AppFeedback.showError(context, message: l10n.commonFailed);
        return;
      }
      final provider = _buildProvider();
      if (widget.providerId == null) {
        ref.read(aiProvidersProvider.notifier).addProvider(provider);
      } else {
        ref.read(aiProvidersProvider.notifier).updateProvider(provider);
      }
      setState(() => _isModified = false);
    }

    final testConnection = widget.testConnection;
    if (testConnection != null) {
      await testConnection();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.commonTest,
        content: SizedBox(
          width: double.maxFinite,
          child: AiStream(
            prompt: generatePromptTest(),
            identifier: widget.providerId,
            regenerate: true,
          ),
        ),
      ),
    );
    cancelActiveAiRequest();
  }
}

class _AddApiKeyDialog extends StatefulWidget {
  const _AddApiKeyDialog({required this.onAdd});

  final void Function(String label, String key) onAdd;

  @override
  State<_AddApiKeyDialog> createState() => _AddApiKeyDialogState();
}

class _AddApiKeyDialogState extends State<_AddApiKeyDialog> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  bool _showValidationError = false;

  @override
  void dispose() {
    _labelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.settingsAiProviderAddKey,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _labelController,
              label: l10n.settingsAiProviderKeyLabel,
            ),
            SizedBox(height: AppSpacing.tokens.s16),
            AppTextField(controller: _keyController, label: 'API Key'),
            if (_showValidationError) ...[
              SizedBox(height: AppSpacing.tokens.s12),
              AppInlineFeedback(message: l10n.commonInputCannotBeEmpty),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppSubmitButton(
          label: l10n.commonConfirm,
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: () async {
            final key = _keyController.text.trim();
            if (key.isEmpty) {
              setState(() => _showValidationError = true);
              return;
            }
            widget.onAdd(_labelController.text, key);
            if (mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
