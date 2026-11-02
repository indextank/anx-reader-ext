import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:path/path.dart' as p;

class BookBottomSheet extends ConsumerStatefulWidget {
  const BookBottomSheet({
    super.key,
    required this.book,
    this.onDelete,
    this.onReplace,
    this.fileLength,
  });

  final Book book;
  final Future<void> Function(Book book)? onDelete;
  final Future<void> Function(Book book, File newFile)? onReplace;
  final Future<int> Function(File file)? fileLength;

  @override
  ConsumerState<BookBottomSheet> createState() => _BookBottomSheetState();
}

class _BookBottomSheetState extends ConsumerState<BookBottomSheet> {
  bool _isReplacing = false;
  bool _isReleasing = false;

  Book get book => widget.book;

  Future<void> _deleteBook() async {
    final onDelete = widget.onDelete;
    if (onDelete != null) {
      await onDelete(book);
      return;
    }
    await bookDao.updateBook(book.copyWith(
      isDeleted: true,
      updateTime: DateTime.now(),
    ));
    await ref.read(bookListProvider.notifier).refresh();
    final bookFile = File(book.fileFullPath);
    if (await bookFile.exists()) await bookFile.delete();
    final coverFile = File(book.coverFullPath);
    if (await coverFile.exists()) await coverFile.delete();
  }

  Future<void> _handleDelete() async {
    final l10n = L10n.of(context);
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: book.title,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription:
          l10n.bookBottomSheetDeleteDangerDescription(book.title),
      onConfirm: _deleteBook,
    );
    if (confirmed && mounted) Navigator.pop(context);
  }

  void _handleDetail() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BookDetail(book: book)),
    );
  }

  Future<void> _releaseBook() async {
    if (_isReleasing) return;
    setState(() => _isReleasing = true);
    try {
      await ref.read(syncProvider.notifier).releaseBook(book);
      await ref.read(syncStatusProvider.notifier).refresh();
    } catch (_) {
      if (mounted) {
        AppFeedback.showError(
          context,
          onRetry: () => _handleUpload(),
        );
      }
    } finally {
      _isReleasing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleUpload() async {
    if (_isReleasing) return;
    if (!Prefs().shouldShowHint(HintKey.releaseLocalSpace)) {
      await _releaseBook();
      return;
    }

    await SmartDialog.show(
      builder: (dialogContext) => AppDialog(
        title: L10n.of(dialogContext).bookSyncStatusReleaseSpaceDialogTitle,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                L10n.of(dialogContext).bookSyncStatusReleaseSpaceDialogContent),
            Row(
              children: [
                StatefulBuilder(
                  builder: (context, setStateDialog) => Checkbox(
                    value: !Prefs().shouldShowHint(HintKey.releaseLocalSpace),
                    onChanged: (value) {
                      Prefs().setShowHint(
                        HintKey.releaseLocalSpace,
                        !(value ?? false),
                      );
                      setStateDialog(() {});
                    },
                  ),
                ),
                Expanded(
                  child: Text(
                    L10n.of(dialogContext).bookSyncStatusDoNotShowAgain,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          AppButton(
            label: L10n.of(dialogContext).commonCancel,
            variant: AppButtonVariant.text,
            onPressed: () => SmartDialog.dismiss(),
          ),
          AppButton(
            label: L10n.of(dialogContext).commonConfirm,
            onPressed: () async {
              await SmartDialog.dismiss();
              await _releaseBook();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleShare() async {
    try {
      await shareFile(
        title: '${book.title}.${book.filePath.split('.').last}',
        filePath: book.fileFullPath,
      );
    } catch (_) {
      if (mounted) AppFeedback.showError(context);
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> _handleReplace() async {
    if (_isReplacing) return;
    setState(() => _isReplacing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || !mounted) return;
      final newFile = result.files.first;
      var extension =
          p.extension(newFile.name).replaceAll('.', '').toLowerCase();
      if (!allowBookExtensions.contains(extension)) {
        AppFeedback.showError(
          context,
          message:
              L10n.of(context).bookBottomSheetUnsupportedFileFormat(extension),
        );
        return;
      }

      Future<int> fileLength(File file) async {
        final readLength = widget.fileLength;
        if (readLength != null) return readLength(file);
        return await file.exists() ? await file.length() : 0;
      }

      final newFileObj = File(newFile.path!);
      final newSize = await fileLength(newFileObj);
      final oldFile = File(book.fileFullPath);
      final oldSize = await fileLength(oldFile);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: L10n.of(dialogContext).commonAttention,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(dialogContext)
                  .bookBottomSheetOriginalFileSize(_formatSize(oldSize))),
              Text(L10n.of(dialogContext)
                  .bookBottomSheetNewFileSize(_formatSize(newSize))),
              SizedBox(height: AppSpacing.tokens.s8),
              Text(
                L10n.of(dialogContext).bookBottomSheetReplaceWarning,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: L10n.of(dialogContext).commonCancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            AppButton(
              label: L10n.of(dialogContext).commonConfirm,
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final onReplace = widget.onReplace;
      if (onReplace != null) {
        await onReplace(book, newFileObj);
        if (mounted) Navigator.pop(context);
        return;
      }

      File fileToProcess = newFileObj;
      if (extension == 'txt') {
        fileToProcess = await convertFromTxt(newFileObj);
        extension = 'epub';
      }
      final title = book.title;
      final nameWithoutExtension =
          '${title.length > 20 ? title.substring(0, 20) : title}-${DateTime.now().millisecondsSinceEpoch}'
              .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
              .replaceAll('\n', '')
              .replaceAll('\r', '')
              .trim();
      final newRelativePath = 'file/$nameWithoutExtension.$extension';
      final newDestPath = getBasePath(newRelativePath);
      await fileToProcess.copy(newDestPath);
      final newMd5 = await MD5Service.calculateFileMd5(newDestPath);
      await bookDao.updateBook(book.copyWith(
        filePath: newRelativePath,
        md5: newMd5,
        updateTime: DateTime.now(),
      ));
      if (book.fileFullPath != newDestPath && await oldFile.exists()) {
        await oldFile.delete();
      }
      if (fileToProcess != newFileObj && await fileToProcess.exists()) {
        await fileToProcess.delete();
      }
      await ref.read(bookListProvider.notifier).refresh();
      if (mounted) Navigator.pop(context);
      if (Prefs().webdavStatus) {
        await ref
            .read(syncProvider.notifier)
            .syncData(SyncDirection.upload, ref);
      }
    } catch (_) {
      if (mounted) AppFeedback.showError(context);
    } finally {
      _isReplacing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final pending = _isReplacing || _isReleasing;
    final actions =
        <({IconData icon, String text, Future<void> Function() onTap})>[
      (
        icon: EvaIcons.share,
        text: l10n.shareFile,
        onTap: _handleShare,
      ),
      (
        icon: EvaIcons.refresh,
        text: l10n.bookBottomSheetReplaceFile,
        onTap: _handleReplace,
      ),
      (
        icon: EvaIcons.cloud_upload,
        text: l10n.bookSyncStatusReleaseSpace,
        onTap: _handleUpload,
      ),
      (
        icon: EvaIcons.more_vertical,
        text: l10n.notesPageDetail,
        onTap: () async => _handleDetail(),
      ),
    ];

    return AppSafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: AppBookshelfTokens.bottomSheetPadding,
        child: Row(
          children: [
            BookCover(
              book: book,
              width: AppBookshelfTokens.bottomSheetCoverWidth,
              height: AppBookshelfTokens.bottomSheetCoverHeight,
            ),
            SizedBox(width: AppBookshelfTokens.bottomSheetSpacing),
            Expanded(
              child: Text(
                book.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AppIconButton(
              icon: EvaIcons.trash,
              variant: AppButtonVariant.danger,
              semanticLabel: l10n.commonDelete,
              tooltip: l10n.commonDelete,
              enabled: !pending,
              onPressed: _handleDelete,
            ),
            PopupMenuButton<Future<void> Function()>(
              tooltip: l10n.more,
              enabled: !pending,
              icon: pending
                  ? const AppLoadingIndicator(
                      size: AppLoadingIndicatorSize.button,
                    )
                  : const Icon(EvaIcons.more_vertical),
              onSelected: (action) => action(),
              itemBuilder: (context) => actions
                  .map(
                    (action) => PopupMenuItem(
                      value: action.onTap,
                      child: Row(
                        children: [
                          Icon(action.icon),
                          SizedBox(width: AppSpacing.tokens.s8),
                          Expanded(child: Text(action.text)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
