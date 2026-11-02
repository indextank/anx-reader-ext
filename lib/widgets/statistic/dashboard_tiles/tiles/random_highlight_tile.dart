import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/providers/random_highlight_provider.dart';
import 'package:anx_reader/utils/date/relative_time_formatter.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RandomHighlightTile extends StatisticsDashboardTileBase {
  const RandomHighlightTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.randomHighlight,
      title: l10n.tileRandomHighlightTitle,
      description: l10n.tileRandomHighlightDescription,
      columnSpan: 2,
      rowSpan: 2,
      icon: Icons.format_quote,
    );
  }

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.format_quote);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    Future<void> retry() =>
        ref.read(randomHighlightProvider.notifier).refresh();
    return DashboardAsyncValue<RandomHighlightData?>(
      value: ref.watch(randomHighlightProvider),
      mock: RandomHighlightData(
        note: BookNote(
          bookId: -1,
          content: 'Stay hungry, stay foolish.',
          cfi: '',
          chapter: 'Mock chapter',
          type: 'highlight',
          color: '000000',
          updateTime: DateTime.now(),
        ),
        book: null,
      ),
      onRetry: retry,
      builder: (data, _) {
        if (data == null) {
          return AppEmptyState(
            compact: true,
            icon: Icons.sticky_note_2_outlined,
            title: L10n.of(context).randomHighlightEmptyState,
            actionLabel: L10n.of(context).commonRefresh,
            onAction: () => retry(),
          );
        }
        return _HighlightCard(data: data, onRefresh: () => retry());
      },
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.data, required this.onRefresh});

  final RandomHighlightData data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Text(data.note.content.trim(),
                style: theme.textTheme.titleMedium),
          ),
        ),
        const Divider(height: 2),
        Text(
          data.book?.title ?? L10n.of(context).randomHighlightUnknownBook,
          style: theme.textTheme.labelLarge,
          overflow: TextOverflow.ellipsis,
        ),
        if (data.note.chapter.isNotEmpty)
          Text(
            data.note.chapter,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                RelativeTimeFormatter.format(data.note.updateTime),
                style: theme.textTheme.bodySmall,
              ),
            ),
            AppIconButton(
              tooltip: L10n.of(context).commonRefresh,
              onPressed: onRefresh,
              icon: Icons.refresh,
            ),
          ],
        ),
      ],
    );
  }
}
