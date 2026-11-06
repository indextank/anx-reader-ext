import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Generic service configuration form widget.
/// Renders form fields based on ConfigItem definitions.
class ServiceConfigForm extends StatefulWidget {
  final List<ConfigItem> configItems;
  final Map<String, dynamic> initialConfig;
  final Function(Map<String, dynamic>) onConfigChanged;

  const ServiceConfigForm({
    super.key,
    required this.configItems,
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<ServiceConfigForm> createState() => _ServiceConfigFormState();
}

class _ServiceConfigFormState extends State<ServiceConfigForm> {
  late Map<String, dynamic> _currentConfig;
  final Map<String, bool> _passwordVisibility = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _currentConfig = Map.from(widget.initialConfig);
    _syncControllers();
  }

  @override
  void didUpdateWidget(ServiceConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final configChanged = oldWidget.initialConfig != widget.initialConfig;
    if (configChanged) {
      _currentConfig = Map.from(widget.initialConfig);
    }
    _syncControllers(updateValues: configChanged);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _textValue(ConfigItem item) {
    return _currentConfig[item.key]?.toString() ??
        item.defaultValue?.toString() ??
        '';
  }

  void _syncControllers({bool updateValues = false}) {
    final textItems = widget.configItems.where(
      (item) => const {
        ConfigItemType.text,
        ConfigItemType.password,
        ConfigItemType.number,
      }.contains(item.type),
    );
    final keys = textItems.map((item) => item.key).toSet();
    for (final key in _controllers.keys.toList()) {
      if (!keys.contains(key)) {
        _controllers.remove(key)!.dispose();
      }
    }
    for (final item in textItems) {
      final value = _textValue(item);
      final controller = _controllers[item.key];
      if (controller == null) {
        _controllers[item.key] = TextEditingController(text: value);
      } else if (updateValues && controller.text != value) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }
  }

  void _updateConfig(String key, dynamic value) {
    setState(() {
      _currentConfig[key] = value;
    });
    widget.onConfigChanged(_currentConfig);
  }

  void _togglePasswordVisibility(String key) {
    setState(() {
      _passwordVisibility[key] = !(_passwordVisibility[key] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.configItems.map((item) {
        return Padding(
          padding: AppSpacing.only(bottom: AppSpacing.tokens.s12),
          child: _buildConfigItem(item),
        );
      }).toList(),
    );
  }

  Widget _buildConfigItem(ConfigItem item) {
    switch (item.type) {
      case ConfigItemType.text:
        return AppTextField(
          label: item.label,
          helperText: item.description,
          controller: _controllers[item.key],
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.password:
        final isVisible = _passwordVisibility[item.key] ?? false;
        final visibilityLabel = isVisible
            ? L10n.of(context).hidePassword
            : L10n.of(context).showPassword;
        return AppTextField(
          obscureText: !isVisible,
          label: item.label,
          helperText: item.description,
          controller: _controllers[item.key],
          suffixIcon: AppIconButton(
            icon: isVisible ? Icons.visibility_off : Icons.visibility,
            tooltip: visibilityLabel,
            semanticLabel: visibilityLabel,
            onPressed: () => _togglePasswordVisibility(item.key),
          ),
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.number:
        return AppTextField(
          label: item.label,
          helperText: item.description,
          keyboardType: TextInputType.number,
          controller: _controllers[item.key],
          onChanged: (value) =>
              _updateConfig(item.key, int.tryParse(value) ?? 0),
        );

      case ConfigItemType.range:
        final double min = item.min ?? 0.0;
        final double max = item.max ?? 100.0;
        final double step = item.step ?? 1.0;
        final double currentValue =
            (_currentConfig[item.key] ?? item.defaultValue ?? min).toDouble();
        final String unit = item.unit ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: AppSpacing.horizontal16,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.tokens.s8,
                children: [
                  Text(item.label,
                      style: Theme.of(context).textTheme.bodyLarge),
                  Text(
                    '${currentValue.round()}$unit',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            if (item.description != null)
              Padding(
                padding: AppSpacing.horizontal16,
                child: Text(
                  item.description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            Slider(
              value: currentValue.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / step).round(),
              label: '${currentValue.round()}$unit',
              onChanged: (value) {
                _updateConfig(item.key, value.round());
              },
            ),
          ],
        );

      case ConfigItemType.toggle:
        return SwitchListTile(
          title: Text(item.label),
          subtitle: item.description != null ? Text(item.description!) : null,
          value: _currentConfig[item.key] ?? item.defaultValue ?? false,
          onChanged: (value) => _updateConfig(item.key, value),
        );

      case ConfigItemType.select:
        if (item.options == null || item.options!.isEmpty) {
          return const AppEmptyState();
        }

        final String currentValue = _currentConfig[item.key]?.toString() ??
            item.defaultValue?.toString() ??
            item.options!.first['value']?.toString() ??
            '';

        return AppDropdownField<String>(
          value: currentValue,
          expandedInsets: EdgeInsets.zero,
          label: item.label,
          helperText: item.description,
          items: [
            for (final option in item.options!)
              AppDropdownItem<String>(
                value: option['value'].toString(),
                label: option['label'].toString(),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              _updateConfig(item.key, value);
            }
          },
        );

      case ConfigItemType.radio:
        if (item.options == null || item.options!.isEmpty) {
          return const AppEmptyState();
        }

        final currentValue = _currentConfig[item.key] ?? item.defaultValue;

        return RadioGroup<dynamic>(
          groupValue: currentValue,
          onChanged: (value) => _updateConfig(item.key, value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: AppSpacing.only(bottom: AppSpacing.tokens.s8),
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (item.description != null)
                Padding(
                  padding: AppSpacing.only(bottom: AppSpacing.tokens.s8),
                  child: Text(item.description!),
                ),
              ...item.options!.map((option) {
                return RadioListTile<dynamic>(
                  title: Text(option['label'].toString()),
                  value: option['value'],
                );
              }),
            ],
          ),
        );

      case ConfigItemType.checkbox:
        return CheckboxListTile(
          title: Text(item.label),
          subtitle: item.description != null ? Text(item.description!) : null,
          value: _currentConfig[item.key] ?? item.defaultValue ?? false,
          onChanged: (value) {
            if (value != null) {
              _updateConfig(item.key, value);
            }
          },
        );

      case ConfigItemType.tip:
        return AppCard(
          padding: AppSpacing.all12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: AppSpacing.tokens.s20,
                    color: context.appTheme.colors.info,
                  ),
                  SizedBox(width: AppSpacing.tokens.s8),
                  Expanded(
                    child: Text(
                      item.defaultValue?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (item.link != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: L10n.of(context).settingsNarrateClickForHelp,
                    variant: AppButtonVariant.text,
                    onPressed: () => launchUrl(
                      Uri.parse(item.link!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }
}
