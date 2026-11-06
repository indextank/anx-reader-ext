import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/search_display_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/search/search_engine.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class SearchEnginesSetting extends StatefulWidget {
  const SearchEnginesSetting({super.key});

  @override
  State<SearchEnginesSetting> createState() => _SearchEnginesSettingState();
}

class _SearchEnginesSettingState extends State<SearchEnginesSetting> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).searchManageEngines)),
      body: AppSafeArea(
        top: false,
        child: settingsSections(
          sections: [
            SettingsSection(
              title: Text(L10n.of(context).searchDisplayMode),
              tiles: [
                SettingsTile(
                  title: RadioGroup<SearchDisplayMode>(
                    groupValue: Prefs().searchDisplayMode,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => Prefs().searchDisplayMode = value);
                      }
                    },
                    child: Column(
                      children: SearchDisplayMode.values.map((mode) {
                        return RadioListTile<SearchDisplayMode>(
                          title: Text(_displayModeLabel(context, mode)),
                          value: mode,
                          contentPadding: AppSpacing.zero,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: Text(L10n.of(context).searchDefaultEngine),
              tiles: [
                SettingsTile(
                  title: AppDropdownField<String>(
                    expandedInsets: EdgeInsets.zero,
                    value: Prefs().selectedSearchEngineId,
                    inputDecorationTheme: AppDropdownField.borderlessDecoration,
                    items: [
                      for (final engine in Prefs().allSearchEngines)
                        AppDropdownItem<String>(
                          value: engine.id,
                          label: engine.name,
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => Prefs().selectedSearchEngineId = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: Text(L10n.of(context).searchManageEngines),
              tiles: [
                ...Prefs().customSearchEngines.map((engine) {
                  return SettingsTile(
                    leading: const Icon(Icons.language),
                    title: Text(engine.name),
                    description: Text(engine.urlTemplate),
                    trailing: AppIconButton(
                      icon: Icons.delete_outline,
                      tooltip: L10n.of(context).commonDelete,
                      onPressed: () => _deleteEngine(engine),
                    ),
                  );
                }),
                SettingsTile.navigation(
                  leading: const Icon(Icons.add),
                  title: Text(L10n.of(context).searchAddEngine),
                  onPressed: (_) => _showAddEngineDialog(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEngine(SearchEngine engine) async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: l10n.removeRule(engine.name),
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: engine.urlTemplate,
      onConfirm: () async {
        Prefs().deleteCustomSearchEngine(engine.id);
        if (mounted) setState(() {});
      },
    );
  }

  String _displayModeLabel(BuildContext context, SearchDisplayMode mode) {
    return switch (mode) {
      SearchDisplayMode.popup => L10n.of(context).searchDisplayModePopup,
      SearchDisplayMode.fullScreen =>
        L10n.of(context).searchDisplayModeFullScreen,
      SearchDisplayMode.external => L10n.of(context).searchDisplayModeExternal,
    };
  }

  Future<void> _showAddEngineDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _AddSearchEngineDialog(),
    );
    if (added == true && mounted) {
      setState(() {});
      AppFeedback.showSuccess(context,
          message: L10n.of(context).searchEngineAdded);
    }
  }
}

class _AddSearchEngineDialog extends StatefulWidget {
  const _AddSearchEngineDialog();

  @override
  State<_AddSearchEngineDialog> createState() => _AddSearchEngineDialogState();
}

class _AddSearchEngineDialogState extends State<_AddSearchEngineDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Prefs().addCustomSearchEngine(
      SearchEngine(
        id: SearchEngine.generateId(),
        name: _nameController.text.trim(),
        urlTemplate: _urlController.text.trim(),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.searchAddEngine,
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: _nameController,
                label: l10n.searchEngineName,
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.searchEngineNameRequired
                    : null,
              ),
              SizedBox(height: AppSpacing.tokens.s16),
              AppTextField(
                controller: _urlController,
                label: l10n.searchEngineUrlTemplate,
                hintText: 'https://example.com/search?q={query}',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.searchEngineUrlRequired;
                  }
                  if (!SearchEngine.isValidUrlTemplate(value.trim())) {
                    return l10n.searchEngineUrlInvalid;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppSubmitButton(label: l10n.commonConfirm, onSubmit: _submit),
      ],
    );
  }
}
