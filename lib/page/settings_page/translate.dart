import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class TranslateSetting extends StatefulWidget {
  const TranslateSetting({super.key});

  @override
  State<TranslateSetting> createState() => _TranslateSettingState();
}

class _TranslateSettingState extends State<TranslateSetting> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppSafeArea(
      top: false,
      child: settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.underlineTranslation),
            tiles: [
              CustomSettingsTile(
                child: _ConfigCard(
                  tip: l10n.underlineTranslationTip,
                  isWarning: false,
                  child: TranslationConfig(setState: () => setState(() {})),
                ),
              ),
              SettingsTile.switchTile(
                title: Text(l10n.readingPageAutoTranslateSelection),
                initialValue: Prefs().autoTranslateSelection,
                onToggle: (value) {
                  setState(() => Prefs().autoTranslateSelection = value);
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.fullTextTranslation),
            tiles: [
              CustomSettingsTile(
                child: _ConfigCard(
                  tip: l10n.fullTextTranslationTip,
                  isWarning: true,
                  child: FullTextTranslationConfig(
                      setState: () => setState(() {})),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.translationServiceConfiguration),
            tiles: [
              for (final service in TranslateService.activeValues)
                CustomSettingsTile(
                    child: TranslateSettingItem(service: service)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.child,
    required this.tip,
    required this.isWarning,
  });

  final Widget child;
  final String tip;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final semanticColors = context.appTheme.colors;
    final color = isWarning ? semanticColors.warning : semanticColors.info;
    return AppCard(
      // 与下方 TranslateSettingItem 卡片的 all8 统一嵌套卡片节奏。
      margin: AppSpacing.all8,
      padding: AppSpacing.all12,
      child: Column(
        children: [
          child,
          SizedBox(height: AppSpacing.tokens.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: color),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Text(
                  tip,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TranslationConfig extends StatelessWidget {
  const TranslationConfig({super.key, required this.setState});

  final VoidCallback setState;

  @override
  Widget build(BuildContext context) {
    return _TranslationConfigBody(
      serviceLabel: Prefs().translateService.getLabel(context),
      fromLabel: Prefs().translateFrom.getNative(context),
      toLabel: Prefs().translateTo.getNative(context),
      onServicePressed: () => _showPicker(
        context,
        const TranslateServicePicker(),
      ).then((_) => setState()),
      onFromPressed: () => _showPicker(
        context,
        const TranslateLangPicker(isFrom: true),
      ).then((_) => setState()),
      onToPressed: () => _showPicker(
        context,
        const TranslateLangPicker(isFrom: false),
      ).then((_) => setState()),
    );
  }
}

class FullTextTranslationConfig extends StatelessWidget {
  const FullTextTranslationConfig({super.key, required this.setState});

  final VoidCallback setState;

  @override
  Widget build(BuildContext context) {
    return _TranslationConfigBody(
      serviceLabel: Prefs().fullTextTranslateService.getLabel(context),
      fromLabel: Prefs().fullTextTranslateFrom.getNative(context),
      toLabel: Prefs().fullTextTranslateTo.getNative(context),
      onServicePressed: () => _showPicker(
        context,
        const FullTextTranslateServicePicker(),
      ).then((_) => setState()),
      onFromPressed: () => _showPicker(
        context,
        const TranslateLangPicker(isFrom: true, isWebView: true),
      ).then((_) => setState()),
      onToPressed: () => _showPicker(
        context,
        const TranslateLangPicker(isFrom: false, isWebView: true),
      ).then((_) => setState()),
    );
  }
}

Future<void> _showPicker(BuildContext context, Widget picker) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => AppSafeArea(top: false, child: picker),
  );
}

class _TranslationConfigBody extends StatelessWidget {
  const _TranslationConfigBody({
    required this.serviceLabel,
    required this.fromLabel,
    required this.toLabel,
    required this.onServicePressed,
    required this.onFromPressed,
    required this.onToPressed,
  });

  final String serviceLabel;
  final String fromLabel;
  final String toLabel;
  final VoidCallback onServicePressed;
  final VoidCallback onFromPressed;
  final VoidCallback onToPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      // 与页面其余行一致的起始对齐（默认 center 会把服务名推到面板中线）。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 与开关/导航行的"标签左、控件右"结构一致；Wrap 在窄屏
        // 放不下时换行而非溢出（Wrap 主轴按内容收缩，需先撑满行宽
        // spaceBetween 才能生效）。
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                L10n.of(context).settingsTranslateCurrentService,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              AppButton(
                label: serviceLabel,
                variant: AppButtonVariant.text,
                onPressed: onServicePressed,
              ),
            ],
          ),
        ),
        const Divider(),
        // 紧凑起始排列：不再用两个 Expanded 平分行宽（那会让语言名
        // 各自悬浮在半区中央，与整页左对齐基准不一致）；窄屏放不下
        // 时自动换行。
        Wrap(
          spacing: AppSpacing.tokens.s8,
          runSpacing: AppSpacing.tokens.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppButton(
              label: fromLabel,
              variant: AppButtonVariant.text,
              onPressed: onFromPressed,
            ),
            const Icon(Icons.arrow_forward_ios),
            AppButton(
              label: toLabel,
              variant: AppButtonVariant.text,
              onPressed: onToPressed,
            ),
          ],
        ),
      ],
    );
  }
}

class TranslateServicePicker extends StatelessWidget {
  const TranslateServicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: TranslateService.activeValues.length,
      itemBuilder: (context, index) {
        final service = TranslateService.activeValues.elementAt(index);
        return AppListTile(
          title: service.getLabel(context),
          onTap: () {
            Prefs().translateService = service;
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class FullTextTranslateServicePicker extends StatelessWidget {
  const FullTextTranslateServicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final services =
        TranslateService.activeValues.where((s) => !s.isWebView).toList();
    return ListView.builder(
      itemCount: services.length,
      itemBuilder: (context, index) => AppListTile(
        title: services[index].getLabel(context),
        onTap: () {
          Prefs().fullTextTranslateService = services[index];
          Navigator.pop(context);
        },
      ),
    );
  }
}

class TranslateLangPicker extends StatelessWidget {
  const TranslateLangPicker({
    super.key,
    required this.isFrom,
    this.isWebView = false,
  });

  final bool isFrom;
  final bool isWebView;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: LangListEnum.values.length,
      itemBuilder: (context, index) {
        final language = LangListEnum.values[index];
        return AppListTile(
          title: language.getNative(context),
          subtitle: language.name[0].toUpperCase() + language.name.substring(1),
          onTap: () {
            if (isWebView) {
              if (isFrom) {
                Prefs().fullTextTranslateFrom = language;
              } else {
                Prefs().fullTextTranslateTo = language;
              }
            } else if (isFrom) {
              Prefs().translateFrom = language;
            } else {
              Prefs().translateTo = language;
            }
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class TranslateSettingItem extends StatefulWidget {
  const TranslateSettingItem({super.key, required this.service});

  final TranslateService service;

  @override
  State<TranslateSettingItem> createState() => _TranslateSettingItemState();
}

class _TranslateSettingItemState extends State<TranslateSettingItem> {
  static const testText = 'Hello, world!';
  bool isExpanded = false;
  Map<String, dynamic> _currentConfig = {};

  @override
  void initState() {
    super.initState();
    _currentConfig = getTranslateServiceConfig(widget.service);
  }

  Future<void> _saveConfig() async {
    saveTranslateServiceConfig(widget.service, _currentConfig);
  }

  Future<void> _test() async {
    await _saveConfig();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: L10n.of(context).commonTest,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      Prefs().translateFrom.getNative(context),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios),
                  Expanded(
                    child: Text(
                      Prefs().translateTo.getNative(context),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const Divider(),
              const Text(testText),
              const Icon(Icons.arrow_downward),
              translateText(testText, service: widget.service),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: L10n.of(context).commonOk,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndCollapse() async {
    await _saveConfig();
    if (!mounted) return;
    setState(() => isExpanded = false);
    AppFeedback.showSuccess(context, message: L10n.of(context).commonSaved);
  }

  @override
  Widget build(BuildContext context) {
    final configItems = getTranslateServiceConfigItems(context, widget.service);
    return AppCard(
      margin: AppSpacing.all8,
      padding: AppSpacing.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppListTile(
            leading: const Icon(Icons.translate_outlined),
            title: widget.service.getLabel(context),
            onTap: () => setState(() => isExpanded = !isExpanded),
          ),
          AnimatedSize(
            duration: AppMotion.tokens.normal,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: AppSpacing.all16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ServiceConfigForm(
                          configItems: configItems,
                          initialConfig: _currentConfig,
                          onConfigChanged: (newConfig) {
                            _currentConfig = newConfig;
                          },
                        ),
                        const Divider(),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.tokens.s8,
                          runSpacing: AppSpacing.tokens.s8,
                          children: [
                            AppSubmitButton(
                              label: L10n.of(context).commonTest,
                              variant: AppButtonVariant.text,
                              feedbackMode: AppSubmitFeedbackMode.inline,
                              onSubmit: _test,
                            ),
                            AppSubmitButton(
                              label: L10n.of(context).commonSave,
                              variant: AppButtonVariant.text,
                              feedbackMode: AppSubmitFeedbackMode.inline,
                              onSubmit: _saveAndCollapse,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
