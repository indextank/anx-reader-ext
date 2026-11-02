import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookFolder extends ConsumerStatefulWidget {
  const BookFolder({
    super.key,
    required this.books,
  });

  final List<Book> books;

  @override
  ConsumerState<BookFolder> createState() => _BookFolderState();
}

class _BookFolderState extends ConsumerState<BookFolder> {
  bool willAcceptBook = false;

  @override
  Widget build(BuildContext context) {
    final folderStyle = ref.watch(
      uiSettingsProvider.select((settings) => settings.bookshelfFolderStyle),
    );

    void onAcceptBook(DragTargetDetails<Book> details) {
      int targetGroupId;
      if (widget.books.first.groupId == 0) {
        ref.read(bookListProvider.notifier).updateBook(
            widget.books.first.copyWith(groupId: widget.books.first.id));
        targetGroupId = widget.books.first.id;
      } else {
        targetGroupId = widget.books.first.groupId;
      }
      ref.read(bookListProvider.notifier).moveBook(details.data, targetGroupId);
    }

    Widget scaleTransition(Widget child) {
      return willAcceptBook
          ? ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                CurvedAnimation(
                  parent: const AlwaysStoppedAnimation(0.5),
                  curve: Curves.easeInOut,
                ),
              ),
              child: child,
            )
          : child;
    }

    bool onWillAcceptBook(DragTargetDetails<Book>? details) {
      if (details?.data.id == widget.books.first.id) return false;
      willAcceptBook = details?.data != null;
      return details?.data != null;
    }

    void onLeaveBook(Book? book) {
      willAcceptBook = false;
    }

    void openFolder(String groupName) {
      showDialog(
        context: context,
        builder: (context) => BookOpenedFolder(
          books: widget.books,
          groupName: groupName,
        ),
      );
    }

    final groupName = ref.watch(groupDaoProvider).whenOrNull(
              data: (groups) => groups
                  .firstWhere(
                    (group) => group.id == widget.books.first.groupId,
                    orElse: () => TbGroup(id: -1, name: '...'),
                  )
                  .name,
            ) ??
        '???';

    final singleBookTarget = DragTarget<Book>(
      onAcceptWithDetails: onAcceptBook,
      onWillAcceptWithDetails: onWillAcceptBook,
      onLeave: onLeaveBook,
      builder: (context, candidateData, rejectedData) {
        return scaleTransition(BookItem(book: widget.books[0]));
      },
    );

    final groupTarget = DragTarget<Book>(
      onAcceptWithDetails: onAcceptBook,
      onWillAcceptWithDetails: onWillAcceptBook,
      onLeave: onLeaveBook,
      builder: (context, candidateData, rejectedData) {
        var count = -1;

        Widget buildStackedPreview() {
          return Stack(
            children: [
              ...widget.books.take(4).map((book) {
                count++;
                return Positioned.fill(
                  right: 0,
                  top: 30 - count * Prefs().bookCoverWidth * 0.12,
                  child: Transform.scale(
                    scale: 1 - (count * 0.08),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AppBookshelfTokens.coverBorderRadius(
                          AppBookshelfTokens.folderRadius,
                        ),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: BookCover(book: book),
                    ),
                  ),
                );
              }),
            ].reversed.toList(),
          );
        }

        Widget buildGridPreview() {
          final previewBooks = widget.books.take(4).toList();
          return Container(
            decoration: BoxDecoration(
              color: AppColors.transparent,
              borderRadius: AppBookshelfTokens.coverBorderRadius(
                AppBookshelfTokens.folderRadius,
              ),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            padding: AppBookshelfTokens.folderPreviewPadding,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: AppBookshelfTokens.folderPreviewAspectRatio,
                mainAxisSpacing: AppBookshelfTokens.folderPreviewMainSpacing,
                crossAxisSpacing: AppBookshelfTokens.folderPreviewCrossSpacing,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                if (index >= previewBooks.length) {
                  return const SizedBox.shrink();
                }
                return BookCover(book: previewBooks[index]);
              },
            ),
          );
        }

        final folderPreview = switch (folderStyle) {
          BookshelfFolderStyle.grid2x2 => buildGridPreview(),
          BookshelfFolderStyle.stacked => buildStackedPreview(),
        };

        return scaleTransition(
          AppCard(
            margin: AppSpacing.zero,
            padding: AppSpacing.all4,
            semanticLabel: groupName,
            onTap: () => openFolder(groupName),
            child: Column(
              children: [
                Expanded(child: folderPreview),
                SizedBox(
                  height: AppBookshelfTokens.folderNameHeight,
                  child: Center(
                    child: Text(
                      groupName,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return RepaintBoundary(
      child: widget.books.length == 1 ? singleBookTarget : groupTarget,
    );
  }
}
