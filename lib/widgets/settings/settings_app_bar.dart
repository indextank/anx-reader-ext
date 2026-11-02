import 'package:anx_reader/design_system/design_system.dart';
import 'package:flutter/material.dart';

AppBar settingsAppBar(String title, BuildContext context) {
  final backTooltip = MaterialLocalizations.of(context).backButtonTooltip;
  return AppBar(
    leading: AppIconButton(
      icon: Icons.arrow_back,
      tooltip: backTooltip,
      semanticLabel: backTooltip,
      onPressed: () => Navigator.pop(context),
    ),
    title: Text(title),
  );
}
