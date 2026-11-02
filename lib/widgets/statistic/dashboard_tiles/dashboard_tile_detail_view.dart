import 'dart:ui';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:heroine/heroine.dart';

class DashboardTileDetailView extends ConsumerStatefulWidget {
  const DashboardTileDetailView({
    super.key,
    required this.tile,
    required this.heroTag,
    this.animationValue = 1.0,
  });

  final StatisticsDashboardTileBase tile;
  final String heroTag;
  final double animationValue;

  @override
  ConsumerState<DashboardTileDetailView> createState() =>
      _DashboardTileDetailViewState();
}

class _DashboardTileDetailViewState
    extends ConsumerState<DashboardTileDetailView> {
  Offset _dragOffset = Offset.zero;
  late double _blurSigma;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _blurSigma = widget.animationValue * AppStatisticsTokens.detailMaxBlur;
  }

  @override
  void didUpdateWidget(DashboardTileDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationValue != widget.animationValue) {
      setState(() {
        _blurSigma = widget.animationValue * AppStatisticsTokens.detailMaxBlur;
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
      final dragBlurFactor = 1.0 -
          (_dragOffset.distance / AppStatisticsTokens.detailMaxDistance)
              .clamp(0.0, 1.0);
      _blurSigma = dragBlurFactor *
          widget.animationValue *
          AppStatisticsTokens.detailMaxBlur;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final shouldDismiss = details.velocity.pixelsPerSecond.distance >
            AppStatisticsTokens.detailDismissVelocity ||
        _dragOffset.distance > AppStatisticsTokens.detailDismissDistance;
    if (shouldDismiss) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _blurSigma = widget.animationValue * AppStatisticsTokens.detailMaxBlur;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSafeArea(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: AppStatisticsTokens.detailAnimationDuration,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.scrim.withValues(
                      alpha: AppStatisticsTokens.detailBackdropAlpha *
                          (widget.animationValue *
                              _blurSigma /
                              AppStatisticsTokens.detailMaxBlur),
                    ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blurSigma,
                  sigmaY: _blurSigma,
                ),
                child: Container(color: AppColors.transparent),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: _isDragging
                ? Duration.zero
                : AppStatisticsTokens.detailSpringDuration,
            curve: Curves.elasticOut,
            left: MediaQuery.of(context).size.width / 2 -
                widget.tile.flipSize(context).width / 2 +
                _dragOffset.dx,
            top: MediaQuery.of(context).size.height / 2 -
                widget.tile.flipSize(context).height / 2 +
                _dragOffset.dy,
            child: GestureDetector(
              onPanStart: (_) => setState(() => _isDragging = true),
              onPanUpdate: _handleDragUpdate,
              onPanEnd: _handleDragEnd,
              child: Heroine(
                tag: widget.heroTag,
                child: widget.tile.buildFlipSide(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
