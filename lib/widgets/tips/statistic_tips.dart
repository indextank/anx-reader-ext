import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class StatisticsTips extends StatelessWidget {
  const StatisticsTips({super.key});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.auto_stories_outlined,
      title: L10n.of(context).statisticsTips_1,
      message: L10n.of(context).statisticsTips_2,
    );
  }
}
