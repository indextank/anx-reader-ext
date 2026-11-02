import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/bookmark.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/bookmark.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookmarkWidget extends ConsumerWidget {
  const BookmarkWidget({
    super.key,
    required this.epubPlayerKey,
    required this.onNavigate,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookId = epubPlayerKey.currentState!.book.id;
    return BookmarkListView(
      value: ref.watch(BookmarkProvider(bookId)),
      onRetry: () async => ref.invalidate(BookmarkProvider(bookId)),
      onTap: (cfi) {
        epubPlayerKey.currentState?.goToCfi(cfi);
        onNavigate();
      },
      onDelete: (id) async {
        ref.read(BookmarkProvider(bookId).notifier).removeBookmark(id: id);
      },
    );
  }
}

class BookmarkListView extends StatelessWidget {
  const BookmarkListView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.onTap,
    required this.onDelete,
  });

  final AsyncValue<List<BookmarkModel>> value;
  final Future<void> Function() onRetry;
  final ValueChanged<String> onTap;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppAsyncValue<List<BookmarkModel>>(
      value: value,
      onRetry: onRetry,
      isEmpty: (bookmarks) => bookmarks.isEmpty,
      emptyBuilder: (context) => AppEmptyState(
        title: l10n.noBookmarks,
        message: l10n.noBookmarksTip,
        icon: Icons.bookmark_border,
      ),
      skeleton: ListView(
        children: const [
          AppCard(child: SizedBox(height: 72)),
          AppCard(child: SizedBox(height: 72)),
          AppCard(child: SizedBox(height: 72)),
        ],
      ),
      dataBuilder: (context, bookmarks) => ListView.builder(
        itemCount: bookmarks.length,
        itemBuilder: (context, index) => Padding(
          padding: AppReadingTokens.listItemGap,
          child: BookmarkItem(
            bookmark: bookmarks[index],
            onTap: onTap,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }
}

class BookmarkItem extends StatelessWidget {
  const BookmarkItem({
    super.key,
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  final BookmarkModel bookmark;
  final ValueChanged<String> onTap;
  final Future<void> Function(int id) onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final id = bookmark.id;
    if (id == null) return;
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: bookmark.content,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: '${l10n.commonDelete}: ${bookmark.chapter}',
      onConfirm: () => onDelete(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return AppCard(
      onTap: () => onTap(bookmark.cfi),
      padding: AppSpacing.all12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bookmark.content, style: Theme.of(context).textTheme.bodyLarge),
          const Divider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bookmark.chapter, style: secondaryStyle),
                    Text(
                      '${(bookmark.percentage * 100).toStringAsFixed(2)}%',
                      style: secondaryStyle,
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: L10n.of(context).commonDelete,
                semanticLabel: L10n.of(context).commonDelete,
                variant: AppButtonVariant.danger,
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
