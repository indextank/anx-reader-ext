import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookItem extends ConsumerWidget {
  const BookItem({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void showBookActions() {
      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (context) => BookBottomSheet(book: book),
      );
    }

    final bookSyncStatus = ref.watch(syncStatusProvider).whenOrNull(
          data: (data) {
            if (data.downloading.contains(book.id)) {
              return BookSyncStatusEnum.downloading;
            } else if (data.uploading.contains(book.id)) {
              return BookSyncStatusEnum.uploading;
            } else if (data.localOnly.contains(book.id)) {
              return BookSyncStatusEnum.localOnly;
            } else if (data.remoteOnly.contains(book.id)) {
              return BookSyncStatusEnum.remoteOnly;
            } else if (data.both.contains(book.id)) {
              return BookSyncStatusEnum.both;
            } else if (data.nonExistent.contains(book.id)) {
              return BookSyncStatusEnum.nonExistent;
            } else {
              return BookSyncStatusEnum.checking;
            }
          },
        ) ??
        BookSyncStatusEnum.checking;

    return AppCard(
      padding: AppSpacing.zero,
      margin: AppSpacing.zero,
      borderRadius: AppRadius.border8,
      semanticLabel: book.title,
      onTap: () => pushToReadingPage(ref, context, book),
      onLongPress: showBookActions,
      onSecondaryTap: showBookActions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: book.coverFullPath,
              child: Row(
                children: [
                  Expanded(child: BookCover(book: book)),
                ],
              ),
            ),
          ),
          SizedBox(height: AppSpacing.tokens.s4),
          SizedBox(
            height: AppBookshelfTokens.bookMetadataHeight,
            child: Padding(
              padding: AppSpacing.symmetric(horizontal: AppSpacing.tokens.s4),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (Prefs().webdavStatus)
                        SizedBox.square(
                          dimension: AppBookshelfTokens.bookSyncIconSize,
                          child: BookSyncStatusIcon(
                            syncStatus: bookSyncStatus,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.author,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.w300),
                        ),
                      ),
                      Text(
                        '${(book.readingPercentage * 100).toStringAsFixed(0)}%',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontWeight: FontWeight.w300),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
