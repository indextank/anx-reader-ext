import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_cache_count.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/user_prompts.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AISettings extends ConsumerStatefulWidget {
  const AISettings({super.key});

  @override
  ConsumerState<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends ConsumerState<AISettings> {
  String? _expandedUserPromptId;
  String? _userPromptValidationErrorId;
  final Map<String, TextEditingController> _userPromptNameControllers = {};
  final Map<String, TextEditingController> _userPromptContentControllers = {};

  @override
  void dispose() {
    for (final controller in _userPromptNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _userPromptContentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final prompts = [
      {
        'identifier': AiPrompts.test,
        'title': l10n.settingsAiPromptTest,
        'variables': ['language_locale'],
      },
      {
        'identifier': AiPrompts.summaryTheChapter,
        'title': l10n.settingsAiPromptSummaryTheChapter,
        'variables': <String>[],
      },
      {
        'identifier': AiPrompts.summaryTheBook,
        'title': l10n.settingsAiPromptSummaryTheBook,
        'variables': <String>[],
      },
      {
        'identifier': AiPrompts.summaryThePreviousContent,
        'title': l10n.settingsAiPromptSummaryThePreviousContent,
        'variables': ['previous_content'],
      },
      {
        'identifier': AiPrompts.translate,
        'title': l10n.settingsAiPromptTranslateAndDictionary,
        'variables': ['text', 'to_locale', 'from_locale', 'contextText'],
      },
      {
        'identifier': AiPrompts.fullTextTranslate,
        'title': l10n.settingsAiPromptFullTextTranslate,
        'variables': ['text', 'to_locale', 'from_locale'],
      },
      {
        'identifier': AiPrompts.mindmap,
        'title': l10n.settingsAiPromptMindmap,
        'variables': <String>[],
      },
    ];

    final promptTile = CustomSettingsTile(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          return SettingsTile.navigation(
            title: Text(prompt['title'] as String),
            onPressed: (context) => _showPromptEditor(
              AiPrompts.values[index],
              prompt['variables'] as List<String>,
            ),
          );
        },
      ),
    );

    final toolDefs = AiToolRegistry.definitions;
    final enabledToolIds = Prefs().enabledAiToolIds;
    final toolsTile = CustomSettingsTile(
      child: Column(
        children: [
          for (final tool in toolDefs)
            SettingsTile.switchTile(
              initialValue: enabledToolIds.contains(tool.id),
              onToggle: (value) {
                final next = Set<String>.from(enabledToolIds);
                if (value) {
                  next.add(tool.id);
                } else {
                  next.remove(tool.id);
                }
                Prefs().enabledAiToolIds = next.toList();
                setState(() {});
              },
              title: Text(tool.displayName(l10n)),
              description: Text(tool.description(l10n)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: l10n.commonReset,
              variant: AppButtonVariant.text,
              onPressed: () {
                Prefs().resetEnabledAiTools();
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );

    return AppSafeArea(
      top: false,
      child: settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.settingsAiServices),
            tiles: [
              SettingsTile.navigation(
                title: Text(l10n.settingsAiProviders),
                description: _buildProviderDescription(),
                onPressed: (context) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AiProviderListPage(),
                    ),
                  );
                },
              ),
              CustomSettingsTile(
                child: _AiRpmTile(onChanged: () => setState(() {})),
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsAiChatDisplay),
            tiles: [
              aiChatDisplayModeTile(),
              if (Prefs().aiChatDisplayMode != AiChatDisplayMode.popup)
                aiPanelPositionTile(),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsAiPrompt),
            tiles: [promptTile],
          ),
          SettingsSection(
            title: Text(l10n.settingsAiUserPrompts),
            tiles: [userPromptsTile()],
          ),
          SettingsSection(
            title: Text(l10n.settingsAiTools),
            tiles: [toolsTile],
          ),
          SettingsSection(
            title: Text(l10n.settingsAiCache),
            tiles: [
              CustomSettingsTile(child: _buildCacheTile()),
              SettingsTile.navigation(
                title: Text(l10n.settingsAiCacheClear),
                onPressed: (context) => _clearCache(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCacheTile() {
    final l10n = L10n.of(context);
    return AppAsyncValue<int>(
      value: ref.watch(aiCacheCountProvider),
      onRetry: _refreshCache,
      dataBuilder: (context, count) => Column(
        children: [
          AppListTile(
            title: l10n.settingsAiCacheSize,
            trailing: Text(l10n.settingsAiCacheCurrentSize(count)),
          ),
          Padding(
            padding: AppSpacing.horizontal16,
            child: Row(
              children: [
                Text(Prefs().maxAiCacheCount.toString()),
                Expanded(
                  child: Semantics(
                    label: l10n.settingsAiCacheSize,
                    value: Prefs().maxAiCacheCount.toString(),
                    child: Slider(
                      value: Prefs().maxAiCacheCount.toDouble(),
                      min: 0,
                      max: AppSettingsAiTokens.cacheSliderMax,
                      divisions: AppSettingsAiTokens.cacheSliderDivisions,
                      label: Prefs().maxAiCacheCount.toString(),
                      onChanged: (value) {
                        Prefs().maxAiCacheCount = value.toInt();
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCache() async {
    ref.invalidate(aiCacheCountProvider);
    await ref.read(aiCacheCountProvider.future);
  }

  Future<void> _clearCache() async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.settingsAiCacheClear,
      message: l10n.settingsAiCacheClear,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.settingsAiCache,
      onConfirm: () => ref.read(aiCacheCountProvider.notifier).clearCache(),
    );
  }

  Widget? _buildProviderDescription() {
    final provider =
        ref.read(aiProvidersProvider.notifier).getSelectedProvider();
    if (provider == null) return null;
    return Text(provider.title);
  }

  AbstractSettingsTile aiChatDisplayModeTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: AppSettingsAiTokens.sectionPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiChatDisplayMode,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AnxSegmentedButton<AiChatDisplayMode>(
                segments: [
                  SegmentButtonItem(
                    value: AiChatDisplayMode.adaptive,
                    label: l10n.settingsAiChatDisplayModeAdaptive,
                    icon: const Icon(
                      Icons.auto_awesome,
                      size: AppSettingsAiTokens.segmentedIconSize,
                    ),
                  ),
                  SegmentButtonItem(
                    value: AiChatDisplayMode.split,
                    label: l10n.settingsAiChatDisplayModeSplit,
                    icon: const Icon(
                      Icons.splitscreen,
                      size: AppSettingsAiTokens.segmentedIconSize,
                    ),
                  ),
                  SegmentButtonItem(
                    value: AiChatDisplayMode.popup,
                    label: l10n.settingsAiChatDisplayModePopup,
                    icon: const Icon(
                      Icons.open_in_new,
                      size: AppSettingsAiTokens.segmentedIconSize,
                    ),
                  ),
                ],
                selected: {Prefs().aiChatDisplayMode},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    Prefs().aiChatDisplayMode = selected.first;
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  AbstractSettingsTile aiPanelPositionTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: AppSettingsAiTokens.sectionPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiPanelPosition,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            AnxSegmentedButton<AiPanelPositionEnum>(
              segments: [
                SegmentButtonItem(
                  value: AiPanelPositionEnum.bottom,
                  label: l10n.settingsAiPanelPositionBottom,
                  icon: const Icon(
                    Icons.vertical_align_bottom,
                    size: AppSettingsAiTokens.segmentedIconSize,
                  ),
                ),
                SegmentButtonItem(
                  value: AiPanelPositionEnum.right,
                  label: l10n.settingsAiPanelPositionRight,
                  icon: const Icon(
                    Icons.border_right,
                    size: AppSettingsAiTokens.segmentedIconSize,
                  ),
                ),
              ],
              selected: {Prefs().aiPanelPosition},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  Prefs().aiPanelPosition = selected.first;
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  AbstractSettingsTile userPromptsTile() {
    final userPrompts = ref.watch(userPromptsProvider);
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppSettingsAiTokens.userPromptPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: l10n.settingsAiUserPromptsAdd,
                    onPressed: _showAddPromptDialog,
                  ),
                ),
                SizedBox(height: AppSpacing.tokens.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: AppSpacing.tokens.s16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: AppSpacing.tokens.s4),
                    Expanded(
                      child: Text(
                        l10n.settingsAiUserPromptsHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (userPrompts.isEmpty)
            AppEmptyState(
              title: l10n.commonEmpty,
              message: l10n.settingsAiUserPromptsEmpty,
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: userPrompts.length,
              itemBuilder: (context, index) {
                final prompt = userPrompts[index];
                return _buildUserPromptItem(
                  prompt,
                  _expandedUserPromptId == prompt.id,
                  index,
                  userPrompts.length,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserPromptItem(
    dynamic prompt,
    bool isExpanded,
    int index,
    int totalCount,
  ) {
    final notifier = ref.read(userPromptsProvider.notifier);
    _userPromptNameControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.name),
    );
    _userPromptContentControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.content),
    );

    return AnimatedSize(
      duration: AppSettingsAiTokens.userPromptAnimationDuration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AppCard(
        margin: AppSettingsAiTokens.userPromptCardMargin,
        padding: AppSettingsAiTokens.userPromptPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  value: prompt.enabled,
                  onChanged: (_) => notifier.toggleEnabled(prompt.id),
                ),
                SizedBox(width: AppSpacing.tokens.s8),
                Expanded(
                  child: Text(
                    prompt.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                AppIconButton(
                  icon: isExpanded ? Icons.expand_less : Icons.edit,
                  onPressed: () {
                    setState(() {
                      _expandedUserPromptId = isExpanded ? null : prompt.id;
                      _userPromptValidationErrorId = null;
                    });
                  },
                  tooltip: L10n.of(context).commonEdit,
                ),
                AppIconButton(
                  icon: Icons.arrow_upward,
                  onPressed: index > 0
                      ? () => notifier.movePrompt(prompt.id, true)
                      : null,
                ),
                AppIconButton(
                  icon: Icons.arrow_downward,
                  onPressed: index < totalCount - 1
                      ? () => notifier.movePrompt(prompt.id, false)
                      : null,
                ),
              ],
            ),
            if (isExpanded) ...[
              const Divider(),
              _buildEditForm(prompt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(dynamic prompt) {
    final l10n = L10n.of(context);
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = _userPromptNameControllers[prompt.id]!;
    final contentController = _userPromptContentControllers[prompt.id]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: nameController,
          label: l10n.settingsAiUserPromptsName,
          maxLength: 50,
        ),
        SizedBox(height: AppSpacing.tokens.s12),
        AppTextField(
          controller: contentController,
          label: l10n.settingsAiUserPromptsContent,
          maxLines: 8,
          minLines: 5,
          maxLength: 2000,
        ),
        if (_userPromptValidationErrorId == prompt.id) ...[
          SizedBox(height: AppSpacing.tokens.s12),
          AppInlineFeedback(message: l10n.commonInputCannotBeEmpty),
        ],
        SizedBox(height: AppSpacing.tokens.s12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.tokens.s8,
          runSpacing: AppSpacing.tokens.s8,
          children: [
            AppButton(
              label: l10n.commonDelete,
              variant: AppButtonVariant.text,
              onPressed: () => _deleteUserPrompt(prompt),
            ),
            AppButton(
              label: l10n.commonSave,
              variant: AppButtonVariant.text,
              onPressed: () {
                final name = nameController.text.trim();
                final content = contentController.text.trim();
                if (name.isEmpty || content.isEmpty) {
                  setState(() => _userPromptValidationErrorId = prompt.id);
                  return;
                }
                notifier.updatePrompt(
                  prompt.copyWith(name: name, content: content),
                );
                setState(() {
                  _expandedUserPromptId = null;
                  _userPromptValidationErrorId = null;
                });
                AppFeedback.showSuccess(
                  context,
                  message: l10n.commonSaveSuccess,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteUserPrompt(dynamic prompt) async {
    final l10n = L10n.of(context);
    final notifier = ref.read(userPromptsProvider.notifier);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: prompt.name,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.settingsAiUserPromptsContent,
      onConfirm: () async {
        notifier.deletePrompt(prompt.id);
        _userPromptNameControllers.remove(prompt.id)?.dispose();
        _userPromptContentControllers.remove(prompt.id)?.dispose();
        if (!mounted) return;
        setState(() {
          _expandedUserPromptId = null;
          _userPromptValidationErrorId = null;
        });
      },
    );
  }

  void _showPromptEditor(AiPrompts identifier, List<String> variables) {
    showDialog<void>(
      context: context,
      builder: (context) => _PromptEditorDialog(
        initialValue: Prefs().getAiPrompt(identifier),
        variables: variables,
        onReset: () {
          Prefs().deleteAiPrompt(identifier);
          return Prefs().getAiPrompt(identifier);
        },
        onSave: (value) => Prefs().saveAiPrompt(identifier, value),
      ),
    );
  }

  Future<void> _showAddPromptDialog() async {
    final notifier = ref.read(userPromptsProvider.notifier);
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => _AddUserPromptDialog(
        onAdd: (name, content) => notifier.addPrompt(
          name: name,
          content: content,
        ),
      ),
    );
    if (added == true && mounted) {
      AppFeedback.showSuccess(
        context,
        message: L10n.of(context).commonAddSuccess,
      );
    }
  }
}

class _PromptEditorDialog extends StatefulWidget {
  const _PromptEditorDialog({
    required this.initialValue,
    required this.variables,
    required this.onReset,
    required this.onSave,
  });

  final String initialValue;
  final List<String> variables;
  final String Function() onReset;
  final void Function(String value) onSave;

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.commonEdit,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: _controller, maxLines: 10),
            Wrap(
              children: [
                for (final variable in widget.variables)
                  AppButton(
                    label: '{{$variable}}',
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.small,
                    onPressed: () => _insertVariable(variable),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l10n.commonReset,
          variant: AppButtonVariant.text,
          onPressed: () {
            setState(() => _controller.text = widget.onReset());
          },
        ),
        AppSubmitButton(
          label: l10n.commonSave,
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: () async {
            widget.onSave(_controller.text);
            if (mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  void _insertVariable(String variable) {
    if (_controller.selection.start == -1 || _controller.selection.end == -1) {
      return;
    }
    final selection = _controller.selection;
    _controller.text = _controller.text.replaceRange(
      selection.start,
      selection.end,
      '{{$variable}}',
    );
  }
}

class _AddUserPromptDialog extends StatefulWidget {
  const _AddUserPromptDialog({required this.onAdd});

  final void Function(String name, String content) onAdd;

  @override
  State<_AddUserPromptDialog> createState() => _AddUserPromptDialogState();
}

class _AddUserPromptDialogState extends State<_AddUserPromptDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _showValidationError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.settingsAiUserPromptsAdd,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _nameController,
              label: l10n.settingsAiUserPromptsName,
              maxLength: 50,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            AppTextField(
              controller: _contentController,
              label: l10n.settingsAiUserPromptsContent,
              maxLines: 8,
              minLines: 5,
              maxLength: 2000,
            ),
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
          onPressed: () => Navigator.pop(context, false),
        ),
        AppSubmitButton(
          label: l10n.commonConfirm,
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: () async {
            final name = _nameController.text.trim();
            final content = _contentController.text.trim();
            if (name.isEmpty || content.isEmpty) {
              setState(() => _showValidationError = true);
              return;
            }
            widget.onAdd(name, content);
            if (mounted) Navigator.pop(context, true);
          },
        ),
      ],
    );
  }
}

class _AiRpmTile extends StatefulWidget {
  const _AiRpmTile({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_AiRpmTile> createState() => _AiRpmTileState();
}

class _AiRpmTileState extends State<_AiRpmTile> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final rpm = Prefs().aiRpm;
    _controller = TextEditingController(text: rpm == 0 ? '' : rpm.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppListTile(
      title: l10n.settingsAiRpm,
      subtitle: l10n.settingsAiRpmTip,
      trailing: SizedBox(
        width: AppSettingsAiTokens.rpmFieldWidth,
        child: AppTextField(
          controller: _controller,
          hintText: '0',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            Prefs().aiRpm = int.tryParse(value) ?? 0;
            widget.onChanged();
          },
        ),
      ),
    );
  }
}
