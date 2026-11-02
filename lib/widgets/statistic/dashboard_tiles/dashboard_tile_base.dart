import 'dart:math';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/service/vibration_service.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/common/fitted_text.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_detail_view.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:heroine/heroine.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

abstract class StatisticsDashboardTileBase {
  const StatisticsDashboardTileBase();

  StatisticsDashboardTileMetadata get metadata;
  StatisticsDashboardTileType get type => metadata.type;

  Widget buildContent(BuildContext context, WidgetRef ref);
  void onRemove(BuildContext context, WidgetRef ref) {}
  Widget buildCorner(BuildContext context, WidgetRef ref) =>
      const SizedBox.shrink();

  L10n get l10nLocal => L10n.of(navigatorKey.currentContext!);

  Widget buildTile(BuildContext context, WidgetRef ref) {
    return SizedBox.expand(
      child: AppCard(
        borderRadius: AppRadius.border16,
        color: Theme.of(context).colorScheme.surfaceContainer,
        padding: AppStatisticsTokens.tilePadding,
        child: Stack(
          children: [
            Positioned(
              bottom: AppStatisticsTokens.cornerOffset,
              right: AppStatisticsTokens.cornerOffset,
              child: Opacity(
                opacity: AppStatisticsTokens.cornerOpacity,
                child: Transform.rotate(
                  angle: AppStatisticsTokens.cornerRotation,
                  child: buildCorner(context, ref),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (title.isNotEmpty)
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                Expanded(child: buildContent(context, ref)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get title => '';
  bool get canFlip => true;
  double get flipSquareSize => AppStatisticsTokens.flipSquareSize;
  double get flipTitleSize => AppStatisticsTokens.flipTitleSize;

  Size tileSize(BuildContext context) {
    final width = min(
      flipSquareSize * metadata.columnSpan,
      MediaQuery.sizeOf(context).width * AppStatisticsTokens.flipWidthFactor,
    );
    final height = min(
      flipSquareSize * metadata.rowSpan,
      MediaQuery.sizeOf(context).height * AppStatisticsTokens.flipHeightFactor,
    );
    return Size(width, height);
  }

  Size flipSize(BuildContext context) {
    final width = min(
      max(
        flipSquareSize * metadata.columnSpan,
        AppStatisticsTokens.flipMinWidth,
      ),
      MediaQuery.sizeOf(context).width * AppStatisticsTokens.flipWidthFactor,
    );
    final height = min(
      flipSquareSize * metadata.rowSpan + flipTitleSize,
      MediaQuery.sizeOf(context).height * AppStatisticsTokens.flipHeightFactor,
    );
    return Size(width, height);
  }

  Widget buildFlipSide(BuildContext context, WidgetRef ref) {
    return flipScaffold(context, ref, buildTile(context, ref));
  }

  void onTap(BuildContext context, WidgetRef ref) {}

  Widget cornerIcon(BuildContext context, IconData iconData) {
    return Icon(
      iconData,
      size: AppStatisticsTokens.cornerIconSize,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Widget cornerText(BuildContext context, String text) {
    return Text(
      text,
      style: AppStatisticsTokens.cornerTextStyle.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget flipScaffold(BuildContext context, WidgetRef ref, Widget flipContent) {
    final theme = Theme.of(context);
    final size = flipSize(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: AppCard(
        color: theme.scaffoldBackgroundColor,
        padding: AppSpacing.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: flipTitleSize -
                  AppStatisticsTokens.flipTitleSpacing -
                  AppStatisticsTokens.flipTitleInset,
              child: AppCard(
                borderRadius: AppRadius.border32,
                padding: AppStatisticsTokens.flipTitlePadding,
                color: theme.colorScheme.primaryContainer,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(metadata.icon, color: theme.colorScheme.primary),
                        const SizedBox(
                          width: AppStatisticsTokens.completionSpacing,
                        ),
                        Expanded(
                          child: FittedText(
                            metadata.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                            maxHeight: AppStatisticsTokens.flipTitleMaxHeight,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      metadata.description,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppStatisticsTokens.flipTitleSpacing),
            Expanded(
              child: Padding(
                padding: AppStatisticsTokens.flipContentMargin,
                child: flipContent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ReorderableItem buildReorderableItem({required BuildContext context}) {
    return ReorderableItem(
      trackingNumber: type.index,
      id: type.name,
      crossAxisCellCount: metadata.columnSpan,
      mainAxisCellCount: metadata.rowSpan,
      child: DashboardTileShell(
        tileType: type,
        tile: this,
        buildContent: buildContent,
      ),
      placeholder: Opacity(
        opacity: AppStatisticsTokens.placeholderOpacity,
        child: DashboardTileShell(
          tileType: type,
          tile: this,
          buildContent: buildContent,
        ),
      ),
    );
  }
}

class DashboardTileShell extends ConsumerWidget {
  const DashboardTileShell({
    super.key,
    required this.buildContent,
    required this.tileType,
    required this.tile,
  });

  final Widget Function(BuildContext context, WidgetRef ref) buildContent;
  final StatisticsDashboardTileType tileType;
  final StatisticsDashboardTileBase tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardTilesProvider);
    final showRemoveButton = state.isEditing && state.workingTiles.length > 1;
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final heroTag = 'dashboard_tile_${tileType.name}';
    return Heroine(
      tag: heroTag,
      flightShuttleBuilder: const FlipShuttleBuilder(
        axis: Axis.vertical,
        halfFlips: 1,
      ),
      motion: Motion.bouncySpring(
        snapToEnd: true,
        duration: AppMotion.tokens.emphasis,
      ),
      child: GestureDetector(
        onTap: () {
          if (!tile.canFlip) {
            tile.onTap(context, ref);
            return;
          }
          VibrationService.medium();
          Navigator.of(context)
              .push(
                PageRouteBuilder(
                  opaque: false,
                  pageBuilder: (context, animation, secondaryAnimation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) => DashboardTileDetailView(
                        tile: tile,
                        heroTag: heroTag,
                        animationValue: animation.value,
                      ),
                    );
                  },
                ),
              )
              .then((_) => VibrationService.rigid());
        },
        child: Stack(
          children: [
            tile.buildTile(context, ref),
            if (showRemoveButton)
              Positioned(
                top: 0,
                right: 0,
                child: AppIconButton(
                  tooltip: L10n.of(context).commonRemove,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    notifier.removeTile(tileType);
                    tile.onRemove(context, ref);
                  },
                  icon: Icons.close,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
