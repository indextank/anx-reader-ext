import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/reading_streak_provider.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingStreakTile extends StatisticsDashboardTileBase {
  const ReadingStreakTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.readingStreak,
      title: l10n.tileReadingStreakTitle,
      description: l10n.tileReadingStreakDescription,
      columnSpan: 2,
      rowSpan: 2,
      icon: Icons.local_fire_department_outlined,
    );
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    return DashboardAsyncValue<ReadingStreakData>(
      value: ref.watch(readingStreakProvider),
      mock: const ReadingStreakData(
        currentStreak: 4,
        longestStreak: 12,
        lastReadingDay: null,
      ),
      onRetry: () async => ref.invalidate(readingStreakProvider),
      builder: (data, _) => _ReadingStreakContent(data: data),
    );
  }
}

class _ReadingStreakContent extends StatelessWidget {
  const _ReadingStreakContent({required this.data});

  final ReadingStreakData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReadToday = _isSameDay(data.lastReadingDay, DateTime.now());
    final fireColor =
        hasReadToday ? theme.colorScheme.primary : theme.colorScheme.outline;
    final l10n = L10n.of(context);
    final encouragement = hasReadToday
        ? l10n.tileReadingStreakEncouragementActive
        : l10n.tileReadingStreakEncouragementInactive;
    final subtitle = hasReadToday
        ? l10n.tileReadingStreakSubtitleActive
        : l10n.tileReadingStreakSubtitleInactive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: fireColor),
            const SizedBox(width: AppStatisticsTokens.librarySpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tileReadingStreakCurrent(data.currentStreak),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: fireColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppStatisticsTokens.librarySpacing),
        Row(
          children: [
            _StatPill(
              label: l10n.tileReadingStreakBestLabel,
              value: l10n.tileReadingStreakCurrent(data.longestStreak),
            ),
          ],
        ),
        const Spacer(),
        Text(encouragement, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  bool _isSameDay(DateTime? date1, DateTime? date2) {
    if (date1 == null || date2 == null) return false;
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: AppStatisticsTokens.streakPillPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.border20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
