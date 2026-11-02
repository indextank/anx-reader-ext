import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

Future<void> showSyncStatusBottomSheet(BuildContext context) async {
  try {
    final dbPath = await getAnxDataBasesPath();
    if (!context.mounted) return;
    await showModalBottomSheet(
      useSafeArea: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SyncStatusBottomSheet(dbPath: dbPath),
    );
  } catch (_) {
    if (context.mounted) {
      AppFeedback.showError(
        context,
        onRetry: () => showSyncStatusBottomSheet(context),
      );
    }
  }
}

class SyncStatusBottomSheet extends ConsumerStatefulWidget {
  const SyncStatusBottomSheet({
    super.key,
    required this.dbPath,
    this.syncStateOverride,
    this.onSyncNow,
    this.onDownloadAll,
  });

  final String dbPath;
  final SyncStateModel? syncStateOverride;
  final Future<void> Function()? onSyncNow;
  final Future<void> Function()? onDownloadAll;

  @override
  ConsumerState<SyncStatusBottomSheet> createState() =>
      _SyncStatusBottomSheetState();
}

enum _SyncAction { sync, download }

class _SyncStatusBottomSheetState extends ConsumerState<SyncStatusBottomSheet> {
  _SyncAction? _pendingAction;
  _SyncAction? _failedAction;
  bool _actionFailed = false;

  Future<void> _runAction(_SyncAction action) async {
    if (_pendingAction != null) return;
    final callback = switch (action) {
      _SyncAction.sync => widget.onSyncNow ??
          () => ref.read(syncProvider.notifier).syncData(
                SyncDirection.both,
                ref,
                trigger: SyncTrigger.manual,
              ),
      _SyncAction.download => widget.onDownloadAll ??
          () async {
            final remoteOnlyIds = ref
                    .read(syncStatusProvider)
                    .whenData((data) => data.remoteOnly)
                    .valueOrNull ??
                <int>[];
            if (remoteOnlyIds.isEmpty) {
              AppFeedback.showInfo(
                context,
                message: L10n.of(context).allBooksAreDownloaded,
              );
              return;
            }
            await ref
                .read(syncProvider.notifier)
                .downloadMultipleBooks(remoteOnlyIds);
          },
    };

    setState(() {
      _pendingAction = action;
      _failedAction = null;
      _actionFailed = false;
    });
    try {
      await callback();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failedAction = action;
          _actionFailed = true;
        });
      }
    } finally {
      _pendingAction = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final SyncStateModel syncState =
        widget.syncStateOverride ?? ref.watch(syncProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final l10n = L10n.of(context);
    final localDb = File(p.join(widget.dbPath, 'app_database.db'));
    final localUpdateTime =
        localDb.existsSync() ? localDb.lastModifiedSync() : null;
    final lastUploadTime = Prefs().lastUploadBookDate;

    return AppSafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: AppBookshelfTokens.syncSheetPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SyncingIndicator(syncState: syncState),
            SizedBox(height: AppSpacing.tokens.s8),
            _UpdateTimeInfo(
              localTime: localUpdateTime,
              lastUploadTime: lastUploadTime,
            ),
            SizedBox(height: AppSpacing.tokens.s24),
            AppAsyncValue<SyncStatusModel>(
              value: syncStatus,
              skeleton: const _SyncStatsSkeleton(),
              onRetry: () => ref.read(syncStatusProvider.notifier).refresh(),
              isEmpty: (data) =>
                  data.localOnly.isEmpty &&
                  data.remoteOnly.isEmpty &&
                  data.both.isEmpty &&
                  data.nonExistent.isEmpty,
              emptyBuilder: (context) => const AppEmptyState(),
              dataBuilder: (context, data) => Column(
                children: [
                  _BookDistributionChart(data: data),
                  _BookStats(data: data),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.tokens.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: AppBookshelfTokens.syncTipIconSize,
                ),
                SizedBox(width: AppSpacing.tokens.s8),
                Expanded(
                  child: Text(
                    l10n.bookSyncStatusNonExistentTip,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (_actionFailed) ...[
              SizedBox(height: AppSpacing.tokens.s12),
              AppInlineFeedback(
                onRetry: _failedAction == null
                    ? null
                    : () => _runAction(_failedAction!),
              ),
            ],
            SizedBox(height: AppSpacing.tokens.s24),
            Wrap(
              spacing: AppSpacing.tokens.s12,
              runSpacing: AppSpacing.tokens.s12,
              children: [
                AppButton(
                  label: l10n.downloadAllBooks,
                  icon: Icons.download_for_offline,
                  variant: AppButtonVariant.outlined,
                  isLoading: _pendingAction == _SyncAction.download,
                  enabled: _pendingAction == null && !syncState.isSyncing,
                  onPressed: () => _runAction(_SyncAction.download),
                ),
                AppButton(
                  label: l10n.syncNow,
                  icon: Icons.sync,
                  isLoading:
                      syncState.isSyncing || _pendingAction == _SyncAction.sync,
                  enabled: _pendingAction == null && !syncState.isSyncing,
                  onPressed: () => _runAction(_SyncAction.sync),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncingIndicator extends StatelessWidget {
  const _SyncingIndicator({required this.syncState});

  final SyncStateModel syncState;

  String _byteToHuman(int byte) {
    if (byte < 1024) return '$byte B';
    if (byte < 1024 * 1024) {
      return '${(byte / 1024).toStringAsFixed(2)} KB';
    }
    if (byte < 1024 * 1024 * 1024) {
      return '${(byte / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${(byte / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (!syncState.isSyncing) {
      return Text(
        l10n.bookSyncStatusNotSyncing,
        style: theme.textTheme.titleMedium,
      );
    }
    final direction = syncState.direction == SyncDirection.upload
        ? l10n.bookSyncStatusUploadingTitle
        : l10n.bookSyncStatusDownloadingTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(direction, style: theme.textTheme.titleMedium),
        Text(syncState.fileName, style: theme.textTheme.bodyMedium),
        SizedBox(height: AppSpacing.tokens.s8),
        LinearProgressIndicator(
          value: syncState.total > 0 ? syncState.count / syncState.total : 0,
        ),
        SizedBox(height: AppSpacing.tokens.s4),
        Text(
          '${_byteToHuman(syncState.count)} / '
          '${_byteToHuman(syncState.total)}',
        ),
        SizedBox(height: AppSpacing.tokens.s16),
        const Divider(),
      ],
    );
  }
}

class _UpdateTimeInfo extends StatelessWidget {
  const _UpdateTimeInfo({
    required this.localTime,
    required this.lastUploadTime,
  });

  final DateTime? localTime;
  final DateTime? lastUploadTime;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = [
      (
        l10n.bookSyncStatusLocalUpdateTime,
        localTime == null
            ? l10n.bookSyncStatusNoSyncYet
            : dateFormatter.format(localTime!),
      ),
      (
        l10n.bookSyncStatusLastSyncTime,
        lastUploadTime == null
            ? l10n.bookSyncStatusNoSyncYet
            : dateFormatter.format(lastUploadTime!),
      ),
    ];
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: AppSpacing.vertical4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(row.$1)),
                  SizedBox(width: AppSpacing.tokens.s8),
                  Flexible(child: Text(row.$2, textAlign: TextAlign.end)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _BookDistributionChart extends StatelessWidget {
  const _BookDistributionChart({required this.data});

  final SyncStatusModel data;

  @override
  Widget build(BuildContext context) {
    final values = [
      (BookSyncStatusEnum.localOnly, data.localOnly.length),
      (BookSyncStatusEnum.remoteOnly, data.remoteOnly.length),
      (BookSyncStatusEnum.both, data.both.length),
      (BookSyncStatusEnum.nonExistent, data.nonExistent.length),
    ];
    final total = values.fold<int>(0, (sum, value) => sum + value.$2);
    return ClipRRect(
      borderRadius: AppRadius.pill,
      child: SizedBox(
        height: AppBookshelfTokens.syncChartHeight,
        child: Row(
          children: values.map((value) {
            final proportion = total == 0 ? 0.0 : value.$2 / total;
            return Expanded(
              flex: (proportion * 100).round(),
              child: Container(
                color:
                    BookSyncStatusIcon(syncStatus: value.$1).colorFor(context),
                child: Center(
                  child: Text(
                    ' ${(proportion * 100).round()}% ',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.white),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BookStats extends StatelessWidget {
  const _BookStats({required this.data});

  final SyncStatusModel data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rows = [
      (
        BookSyncStatusEnum.localOnly,
        l10n.bookSyncStatusLocalOnlyBooks,
        data.localOnly.length,
      ),
      (
        BookSyncStatusEnum.remoteOnly,
        l10n.bookSyncStatusRemoteOnlyBooks,
        data.remoteOnly.length,
      ),
      (
        BookSyncStatusEnum.both,
        l10n.bookSyncStatusBothBooks,
        data.both.length,
      ),
      (
        BookSyncStatusEnum.nonExistent,
        l10n.bookSyncStatusNonExistentBooks,
        data.nonExistent.length,
      ),
    ];
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: AppSpacing.vertical4,
              child: Row(
                children: [
                  BookSyncStatusIcon(syncStatus: row.$1),
                  SizedBox(width: AppSpacing.tokens.s8),
                  Expanded(child: Text(row.$2)),
                  Text(
                    l10n.bookSyncStatusBooksCount(row.$3),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SyncStatsSkeleton extends StatelessWidget {
  const _SyncStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: AppBookshelfTokens.syncChartHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        SizedBox(height: AppSpacing.tokens.s12),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: AppSpacing.vertical4,
            child: Container(
              height: AppSpacing.tokens.s20,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
      ],
    );
  }
}
