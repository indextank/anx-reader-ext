import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';

final _currentPageIndexProvider = StateProvider<int>((ref) => 0);

class StatisticsDashboardTitle extends ConsumerWidget {
  const StatisticsDashboardTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final availableTiles = notifier.availableTiles;
    final l10n = L10n.of(context);
    void showAddTileSheet() {
      if (availableTiles.isEmpty) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.transparent,
        builder: (context) => const AddTileSheetContent(),
      );
    }

    return Row(
      children: [
        const Expanded(child: TotalReadTime()),
        if (tilesState.isEditing) ...[
          AppIconButton(
            onPressed: availableTiles.isEmpty ? null : showAddTileSheet,
            icon: Icons.add,
            tooltip: l10n.statisticsDashboardAddCard,
          ),
          const SizedBox(width: AppStatisticsTokens.librarySpacing),
          AppIconButton(
            onPressed: notifier.saveLayout,
            icon: Icons.save,
            tooltip: l10n.commonSave,
          ),
        ],
      ],
    );
  }
}

class AddTileSheetContent extends ConsumerStatefulWidget {
  const AddTileSheetContent({super.key});

  @override
  ConsumerState<AddTileSheetContent> createState() =>
      _AddTileSheetContentState();
}

class _AddTileSheetContentState extends ConsumerState<AddTileSheetContent> {
  late final List<StatisticsDashboardTileType> availableTiles;

  @override
  void initState() {
    super.initState();
    availableTiles = ref.read(dashboardTilesProvider.notifier).availableTiles;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final currentIndex = ref.watch(_currentPageIndexProvider);
    if (availableTiles.isEmpty) {
      return const AppEmptyState();
    }
    final validIndex = currentIndex.clamp(0, availableTiles.length - 1);
    if (currentIndex != validIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(_currentPageIndexProvider.notifier).state = validIndex;
        }
      });
    }
    final l10n = L10n.of(context);
    return AppSafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height *
            AppStatisticsTokens.addTileSheetHeightFactor,
        child: AppCard(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: AppSpacing.zero,
          child: Column(
            children: [
              Padding(
                padding: AppStatisticsTokens.addTilePadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.statisticsDashboardAddTileTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    AppIconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icons.close,
                      tooltip: l10n.commonCancel,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IntroductionScreen(
                  showDoneButton: false,
                  pages: availableTiles.map((type) {
                    final dashboardTile = dashboardTileRegistry[type]!;
                    final metadata = dashboardTile.metadata;
                    return PageViewModel(
                      titleWidget: Text(
                        metadata.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      bodyWidget: Column(
                        children: [
                          SizedBox(
                            height: dashboardTile.tileSize(context).height,
                            width: dashboardTile.tileSize(context).width,
                            child: dashboardTile.buildTile(context, ref),
                          ),
                          const SizedBox(
                            height: AppStatisticsTokens.addTilePreviewSpacing,
                          ),
                          Text(
                            metadata.description,
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      decoration: const PageDecoration(
                        bodyPadding: AppSpacing.zero,
                        pageMargin: AppSpacing.zero,
                      ),
                    );
                  }).toList(),
                  onDone: () {},
                  onChange: (index) {
                    ref.read(_currentPageIndexProvider.notifier).state = index;
                  },
                  showBackButton: false,
                  showNextButton: false,
                  dotsDecorator: DotsDecorator(
                    size: AppStatisticsTokens.addTileDotSize,
                    activeSize: AppStatisticsTokens.addTileActiveDotSize,
                    activeColor: Theme.of(context).colorScheme.primary,
                    color: Theme.of(context).colorScheme.outlineVariant,
                    spacing: AppStatisticsTokens.addTileDotSpacing,
                    activeShape: RoundedRectangleBorder(
                      borderRadius: AppRadius.pill,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: AppStatisticsTokens.addTilePadding,
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    enabled: !notifier.workingTiles
                        .contains(availableTiles[validIndex]),
                    onPressed: () {
                      notifier.addTile(availableTiles[validIndex]);
                      setState(() {});
                    },
                    icon: Icons.add,
                    label: l10n.statisticsDashboardAddTileButton(
                      dashboardTileRegistry[availableTiles[validIndex]]!
                          .metadata
                          .title,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TotalReadTime extends ConsumerWidget {
  const TotalReadTime({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardAsyncValue<int>(
      value: ref.watch(totalReadingTimeProvider),
      mock: 0,
      onRetry: () async => ref.invalidate(totalReadingTimeProvider),
      builder: (seconds, _) {
        final hours = seconds ~/ 3600;
        final minutes = (seconds % 3600) ~/ 60;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: [
                highlightDigit(
                  context,
                  L10n.of(context).commonHours(hours),
                  AppStatisticsTokens.totalTimeDigitStyle,
                  AppStatisticsTokens.totalTimeStyle,
                ),
                highlightDigit(
                  context,
                  L10n.of(context).commonMinutes(minutes),
                  AppStatisticsTokens.totalTimeDigitStyle,
                  AppStatisticsTokens.totalTimeStyle,
                ),
              ],
            ),
            Text(
              '${Prefs().beginDate.toString().substring(0, 10)} '
              '${L10n.of(context).statisticToPresent}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}
