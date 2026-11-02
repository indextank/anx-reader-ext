import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/widgets/bookshelf/spining_sync_icon.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

class BookSyncStatusIcon extends StatelessWidget {
  const BookSyncStatusIcon({
    super.key,
    required this.syncStatus,
    this.iconSize = 16,
  });

  final BookSyncStatusEnum syncStatus;
  final double iconSize;

  Color colorFor(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final semantic = context.appTheme.colors;
    return switch (syncStatus) {
      BookSyncStatusEnum.localOnly => semantic.warning,
      BookSyncStatusEnum.remoteOnly => theme.onSurfaceVariant,
      BookSyncStatusEnum.both => semantic.success,
      BookSyncStatusEnum.nonExistent => semantic.error,
      BookSyncStatusEnum.downloading => semantic.info,
      BookSyncStatusEnum.uploading => semantic.info,
      BookSyncStatusEnum.checking => theme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context);
    final child = switch (syncStatus) {
      BookSyncStatusEnum.localOnly => Stack(
          children: [
            Center(child: Icon(Bootstrap.cloud, color: color, size: iconSize)),
            Center(
              child: Icon(Bootstrap.x, color: color, size: iconSize * 0.7),
            ),
          ],
        ),
      BookSyncStatusEnum.remoteOnly => Stack(
          children: [
            Center(child: Icon(Bootstrap.cloud, color: color, size: iconSize)),
            Center(
              child: Icon(Icons.sync, color: color, size: iconSize * 0.5),
            ),
          ],
        ),
      BookSyncStatusEnum.both => Icon(
          Bootstrap.cloud_check,
          color: color,
          size: iconSize,
        ),
      BookSyncStatusEnum.nonExistent => Icon(
          OctIcons.x_circle,
          color: color,
          size: iconSize * 0.8,
        ),
      BookSyncStatusEnum.downloading => Stack(
          children: [
            Center(
              child: SpiningSyncIcon(size: iconSize, color: color),
            ),
            Center(
              child: Icon(
                Bootstrap.arrow_down_short,
                color: color,
                size: iconSize * 0.7,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.uploading => Stack(
          children: [
            Center(
              child: SpiningSyncIcon(size: iconSize, color: color),
            ),
            Center(
              child: Icon(
                Bootstrap.arrow_up_short,
                color: color,
                size: iconSize * 0.7,
              ),
            ),
          ],
        ),
      BookSyncStatusEnum.checking => const Center(
          child: AppLoadingIndicator(size: AppLoadingIndicatorSize.button),
        ),
    };
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
}
