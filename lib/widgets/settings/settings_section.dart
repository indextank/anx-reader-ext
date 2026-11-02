import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

abstract class AbstractSettingsSection extends StatelessWidget {
  const AbstractSettingsSection({super.key});
}

class SettingsSection extends AbstractSettingsSection {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.margin,
    this.title,
  });

  final List<AbstractSettingsTile> tiles;
  final EdgeInsetsDirectional? margin;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return buildSectionBody(context);
  }

  Widget buildSectionBody(BuildContext context) {
    final tileList = buildTileList();

    if (title == null) {
      return tileList;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSettingsTokens.sectionTitlePadding,
          child: DefaultTextStyle(
            style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle())
                .copyWith(color: Theme.of(context).colorScheme.primary),
            child: title!,
          ),
        ),
        AppCard(
          margin: margin ?? AppSpacing.horizontal8,
          padding: AppSpacing.zero,
          child: tileList,
        ),
      ],
    );
  }

  Widget buildTileList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: tiles,
    );
  }
}

class CustomSettingsSection extends AbstractSettingsSection {
  const CustomSettingsSection({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
