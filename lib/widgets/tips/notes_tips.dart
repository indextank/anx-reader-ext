import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class NotesTips extends StatelessWidget {
  const NotesTips({super.key});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.auto_stories_outlined,
      title: L10n.of(context).notesTips_1,
      message: L10n.of(context).notesTips_2,
    );
  }
}
