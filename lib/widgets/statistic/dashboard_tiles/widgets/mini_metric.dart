import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:flutter/material.dart';

class DashboardMiniMetric extends StatelessWidget {
  const DashboardMiniMetric({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  final int value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: AppStatisticsTokens.miniMetricIconSize,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppStatisticsTokens.miniMetricSpacing),
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          ],
        ),
        const SizedBox(height: AppStatisticsTokens.miniMetricSpacing),
        Text(
          value.toString(),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
