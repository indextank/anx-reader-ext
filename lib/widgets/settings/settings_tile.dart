import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

abstract class AbstractSettingsTile extends StatelessWidget {
  const AbstractSettingsTile({super.key});
}

enum SettingsTileType { simpleTile, switchTile, navigationTile }

class SettingsTile extends AbstractSettingsTile {
  SettingsTile({
    this.leading,
    this.trailing,
    this.value,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    onToggle = null;
    initialValue = null;
    activeSwitchColor = null;
    tileType = SettingsTileType.simpleTile;
  }

  SettingsTile.navigation({
    this.leading,
    this.trailing,
    this.value,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    onToggle = null;
    initialValue = null;
    activeSwitchColor = null;
    tileType = SettingsTileType.navigationTile;
  }

  SettingsTile.switchTile({
    required this.initialValue,
    required this.onToggle,
    this.activeSwitchColor,
    this.leading,
    this.trailing,
    required this.title,
    this.description,
    this.onPressed,
    this.enabled = true,
    super.key,
  }) {
    value = null;
    tileType = SettingsTileType.switchTile;
  }

  /// The widget at the beginning of the tile
  final Widget? leading;

  /// The Widget at the end of the tile
  final Widget? trailing;

  /// The widget at the center of the tile
  final Widget title;

  /// The widget at the bottom of the [title]
  final Widget? description;

  /// A function that is called by tap on a tile
  final Function(BuildContext context)? onPressed;

  late final Color? activeSwitchColor;
  late final Widget? value;
  late final Function(bool value)? onToggle;
  late final SettingsTileType tileType;
  late final bool? initialValue;
  late final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AndroidSettingsTile(
      description: description,
      onPressed: onPressed,
      onToggle: onToggle,
      tileType: tileType,
      value: value,
      leading: leading,
      title: title,
      enabled: enabled,
      activeSwitchColor: activeSwitchColor,
      initialValue: initialValue ?? false,
      trailing: trailing,
    );
  }
}

class AndroidSettingsTile extends StatelessWidget {
  const AndroidSettingsTile({
    required this.tileType,
    required this.leading,
    required this.title,
    required this.description,
    required this.onPressed,
    required this.onToggle,
    required this.value,
    required this.initialValue,
    required this.activeSwitchColor,
    required this.enabled,
    required this.trailing,
    super.key,
  });

  final SettingsTileType tileType;
  final Widget? leading;
  final Widget? title;
  final Widget? description;
  final Function(BuildContext context)? onPressed;
  final Function(bool value)? onToggle;
  final Widget? value;
  final bool initialValue;
  final bool enabled;
  final Color? activeSwitchColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canActivate = tileType == SettingsTileType.switchTile
        ? onToggle != null || onPressed != null
        : onPressed != null;
    final subtitle = value ?? description;
    final foreground =
        enabled ? theme.textTheme.titleMedium?.color : theme.disabledColor;

    Widget? buildTrailing() {
      if (tileType == SettingsTileType.switchTile) {
        final switchWidget = Switch(
          value: initialValue,
          onChanged: enabled ? onToggle : null,
          activeThumbColor: enabled ? activeSwitchColor : theme.disabledColor,
        );
        if (trailing == null) return switchWidget;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: trailing!),
            SizedBox(width: AppSpacing.tokens.s8),
            switchWidget,
          ],
        );
      }
      if (tileType == SettingsTileType.navigationTile) {
        return trailing ?? const Icon(Icons.chevron_right_sharp);
      }
      return trailing;
    }

    return ListTile(
      enabled: enabled,
      leading: leading,
      title: DefaultTextStyle(
        style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
          color: foreground,
          fontWeight: FontWeight.w400,
        ),
        child: title ?? const SizedBox.shrink(),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: AppSpacing.only(top: AppSpacing.tokens.s4),
              child: DefaultTextStyle(
                style:
                    (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.disabledColor,
                ),
                child: subtitle,
              ),
            ),
      trailing: buildTrailing(),
      onTap: !enabled || !canActivate
          ? null
          : () {
              if (tileType == SettingsTileType.switchTile) {
                onToggle?.call(!initialValue);
              } else {
                onPressed?.call(context);
              }
            },
      contentPadding: AppSettingsTokens.tileContentPadding,
      minTileHeight: AppSpacing.tokens.s48,
    );
  }
}

class CustomSettingsTile extends AbstractSettingsTile {
  const CustomSettingsTile({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
