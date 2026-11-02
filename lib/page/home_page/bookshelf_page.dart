import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/sort_field.dart';
import 'package:anx_reader/enums/sort_order.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/page/search/search_page.dart';
import 'package:anx_reader/providers/book_filters.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/color/hash_color.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder.dart';
import 'package:anx_reader/widgets/bookshelf/sync_button.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/common/tag_chip.dart';
import 'package:anx_reader/widgets/hint/hint_banner.dart';
import 'package:anx_reader/widgets/tips/bookshelf_tips.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/custom_draggable.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:path/path.dart' as p;

class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({
    super.key,
    this.controller,
    this.syncButton,
    this.copyToTempFile,
    this.importBooks,
  });

  final ScrollController? controller;
  final Widget? syncButton;
  final Future<File> Function({
    required String sourcePath,
    required String fileName,
  })? copyToTempFile;
  final FutureOr<void> Function(
    List<File> files,
    BuildContext context,
    WidgetRef ref,
  )? importBooks;

  @override
  ConsumerState<BookshelfPage> createState() => BookshelfPageState();
}

class BookshelfPageState extends ConsumerState<BookshelfPage>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  late final bool _ownsScrollController = widget.controller == null;
  final _gridViewKey = GlobalKey();
  final GlobalKey _tagButtonKey = GlobalKey();
  final TextEditingController _editTagController = TextEditingController();
  bool _dragging = false;
  bool _importing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _editTagController.dispose();
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  Future<File> _copyToTempFile({
    required String sourcePath,
    required String fileName,
  }) async {
    final copyToTempFile = widget.copyToTempFile;
    if (copyToTempFile != null) {
      return copyToTempFile(sourcePath: sourcePath, fileName: fileName);
    }
    final tempDir = await getAnxTempDir();
    final targetPath = p.join(tempDir.path, fileName);
    final targetFile = File(targetPath);
    if (await targetFile.exists()) await targetFile.delete();
    return File(sourcePath).copy(targetPath);
  }

  Future<void> _importFiles(List<File> files) async {
    if (!mounted) return;
    final importBooks = widget.importBooks;
    if (importBooks != null) {
      await importBooks(files, context, ref);
      return;
    }
    importBookList(files, context, ref);
  }

  Future<void> _importBook() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (result == null) return;
      final files = result.files;
      AnxLog.info('importBook files: ${files.toString()}');
      final fileList = AnxPlatform.isAndroid
          ? files.map((file) => File(file.path!)).toList()
          : await Future.wait(files.map((file) {
              return _copyToTempFile(
                sourcePath: file.path!,
                fileName: file.name,
              );
            }));
      await _importFiles(fileList);
    } catch (_) {
      if (mounted) {
        AppFeedback.showError(context, onRetry: _importBook);
      }
    } finally {
      _importing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final statusFilter = ref.watch(readingStatusFilterNotifierProvider);
    final selectedTags = ref.watch(tagSelectionProvider);
    final tagsAsync = ref.watch(tagListProvider);

    Widget buildFilterBar() {
      final statusChips = [
        _StatusChip(
          label: L10n.of(context).bookshelfFilterFinished,
          selected: statusFilter == ReadingStatusFilter.finished,
          onTap: () {
            ref
                .read(readingStatusFilterNotifierProvider.notifier)
                .toggle(ReadingStatusFilter.finished);
            ref.read(bookListProvider.notifier).refresh();
          },
        ),
        _StatusChip(
          label: L10n.of(context).bookshelfFilterReading,
          selected: statusFilter == ReadingStatusFilter.reading,
          onTap: () {
            ref
                .read(readingStatusFilterNotifierProvider.notifier)
                .toggle(ReadingStatusFilter.reading);
            ref.read(bookListProvider.notifier).refresh();
          },
        ),
        _StatusChip(
          label: L10n.of(context).bookshelfFilterNotStarted,
          selected: statusFilter == ReadingStatusFilter.notStarted,
          onTap: () {
            ref
                .read(readingStatusFilterNotifierProvider.notifier)
                .toggle(ReadingStatusFilter.notStarted);
            ref.read(bookListProvider.notifier).refresh();
          },
        ),
      ];

      Future<void> showTagEditDialog(Tag tag) async {
        await TagChip.showEditDialog(
          context: context,
          initialName: tag.name,
          initialColor: tag.color ?? hashColor(tag.name),
          onRename: (newName) async {
            await ref
                .read(tagListProvider.notifier)
                .updateTag(tag.id, newName: newName);
            ref.read(bookListProvider.notifier).refresh();
          },
          onColorChange: (color) async {
            await ref
                .read(tagListProvider.notifier)
                .updateTag(tag.id, color: color);
            ref.read(bookListProvider.notifier).refresh();
          },
          onDelete: () async {
            await ref.read(tagListProvider.notifier).deleteTag(tag.id);
            if (selectedTags.contains(tag.id)) {
              ref.read(tagSelectionProvider.notifier).toggle(tag.id);
            }
            ref.read(bookListProvider.notifier).refresh();
          },
        );
      }

      Future<void> showTagMenu() async {
        final tags = tagsAsync.when(
          data: (value) => value,
          loading: () => const <Tag>[],
          error: (_, __) => const <Tag>[],
        );
        if (!mounted) return;
        final renderBox =
            _tagButtonKey.currentContext?.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (renderBox == null || overlay == null) return;
        final position = RelativeRect.fromRect(
          Rect.fromPoints(
            renderBox.localToGlobal(Offset.zero, ancestor: overlay),
            renderBox.localToGlobal(
              renderBox.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          ),
          Offset.zero & overlay.size,
        );
        final liveSelected = {...selectedTags};
        final boxMaxWidth = min(
          MediaQuery.of(context).size.width *
              AppBookshelfTokens.tagMenuWidthFactor,
          AppBookshelfTokens.tagMenuMinWidth,
        );

        await showMenu<int>(
          color: AppColors.transparent,
          shadowColor: AppColors.transparent,
          context: context,
          position: position,
          constraints: const BoxConstraints(
            maxHeight: AppBookshelfTokens.tagMenuMaxHeight,
          ),
          items: [
            PopupMenuItem<int>(
              enabled: false,
              padding: AppSpacing.zero,
              child: Align(
                alignment: Alignment.topRight,
                child: FilledContainer(
                  constraints: BoxConstraints(
                    maxHeight: AppBookshelfTokens.tagMenuContentMaxHeight,
                    maxWidth: boxMaxWidth,
                  ),
                  padding: AppBookshelfTokens.tagMenuPadding,
                  child: StatefulBuilder(
                    builder: (context, setStateMenu) {
                      return SingleChildScrollView(
                        child: Wrap(
                          spacing: AppSpacing.tokens.s8,
                          runSpacing: AppSpacing.tokens.s8,
                          children: [
                            if (tags.isEmpty)
                              Text(
                                L10n.of(context).tagsEmptyHint,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            if (tags.isNotEmpty)
                              TagChip(
                                label: L10n.of(context).noTagFilter,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                selected: liveSelected.contains(kNoTagFilterId),
                                onTap: () {
                                  setStateMenu(() {
                                    if (liveSelected.contains(kNoTagFilterId)) {
                                      liveSelected.remove(kNoTagFilterId);
                                    } else {
                                      liveSelected.clear();
                                      liveSelected.add(kNoTagFilterId);
                                    }
                                  });
                                  ref
                                      .read(tagSelectionProvider.notifier)
                                      .toggle(kNoTagFilterId);
                                  ref.read(bookListProvider.notifier).refresh();
                                },
                                dense: false,
                              ),
                            for (final tag in tags)
                              TagChip(
                                label: tag.name,
                                color: tag.color,
                                selected: liveSelected.contains(tag.id),
                                onTap: () {
                                  setStateMenu(() {
                                    if (liveSelected.contains(tag.id)) {
                                      liveSelected.remove(tag.id);
                                    } else {
                                      liveSelected.remove(kNoTagFilterId);
                                      liveSelected.add(tag.id);
                                    }
                                  });
                                  ref
                                      .read(tagSelectionProvider.notifier)
                                      .toggle(tag.id);
                                  ref.read(bookListProvider.notifier).refresh();
                                },
                                onLongPress: () {
                                  Navigator.of(context).pop();
                                  Future.microtask(
                                    () => showTagEditDialog(tag),
                                  );
                                },
                                dense: false,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      }

      final selectedTagWidgets = tagsAsync.when(
        data: (tags) {
          final tagMap = {for (final tag in tags) tag.id: tag};
          final chips = <Widget>[];
          if (selectedTags.contains(kNoTagFilterId)) {
            chips.add(
              Padding(
                padding: AppBookshelfTokens.selectedTagPadding,
                child: TagChip(
                  label: L10n.of(context).noTagFilter,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  selected: true,
                  onTap: () {
                    ref
                        .read(tagSelectionProvider.notifier)
                        .toggle(kNoTagFilterId);
                    ref.read(bookListProvider.notifier).refresh();
                  },
                  dense: true,
                ),
              ),
            );
          }
          chips.addAll(
            selectedTags
                .where((id) => id != kNoTagFilterId)
                .map((id) => tagMap[id])
                .whereType<Tag>()
                .map(
                  (tag) => Padding(
                    padding: AppBookshelfTokens.selectedTagPadding,
                    child: TagChip(
                      label: tag.name,
                      color: tag.color,
                      selected: true,
                      onTap: () {
                        ref.read(tagSelectionProvider.notifier).toggle(tag.id);
                        ref.read(bookListProvider.notifier).refresh();
                      },
                      dense: true,
                    ),
                  ),
                ),
          );
          return Row(children: chips);
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      );

      return Container(
        height: AppBookshelfTokens.filterBarHeight,
        padding: AppBookshelfTokens.filterBarPadding,
        child: Row(
          children: [
            SizedBox(width: AppSpacing.tokens.s8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [...statusChips, selectedTagWidgets]),
              ),
            ),
            AppIconButton(
              key: _tagButtonKey,
              icon: EvaIcons.pricetags_outline,
              tooltip: L10n.of(context).bookshelfFilterTagsTooltip,
              semanticLabel: L10n.of(context).bookshelfFilterTagsTooltip,
              onPressed: showTagMenu,
            ),
          ],
        ),
      );
    }

    void handleBottomSheet(BuildContext context, Book book) {
      showBottomSheet(
        context: context,
        builder: (context) => BookBottomSheet(book: book),
      );
    }

    List<int> lockedIndices = [];
    final buildBookshelfBody = AppAsyncValue<List<List<Book>>>(
      value: ref.watch(bookListProvider),
      onRetry: () => ref.read(bookListProvider.notifier).refresh(),
      skeleton: GridView.builder(
        padding: AppBookshelfTokens.gridPadding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: AppBookshelfTokens.gridAspectRatio,
          mainAxisSpacing: AppBookshelfTokens.gridMainSpacing,
          crossAxisSpacing: AppBookshelfTokens.gridCrossSpacing,
        ),
        itemCount: AppBookshelfTokens.skeletonItemCount,
        itemBuilder: (context, index) => AppCard(
          margin: AppSpacing.zero,
          padding: AppSpacing.zero,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      isEmpty: (books) => books.isEmpty,
      emptyBuilder: (context) => const BookshelfTips(),
      dataBuilder: (context, books) {
        for (var i = 0; i < books.length; i++) {
          if (books[i].length != 1) lockedIndices.add(i);
        }
        return ReorderableBuilder(
          lockedIndices: lockedIndices,
          enableDraggable: true,
          longPressDelay: const Duration(milliseconds: 300),
          onReorder: (ReorderedListFunction reorderedListFunction) {},
          scrollController: _scrollController,
          onDragStarted: (index) {
            if (books[index].length == 1) {
              handleBottomSheet(context, books[index].first);
              for (var i = 0; i < books.length; i++) {
                if (i != index) lockedIndices.add(i);
              }
            }
          },
          onDragEnd: (index) {
            lockedIndices = [];
            for (var i = 0; i < books.length; i++) {
              if (books[i].length != 1) lockedIndices.add(i);
            }
            setState(() {});
          },
          children: [
            ...books.map((book) {
              final topLevelKey = ValueKey<String>(book.first.id.toString());
              return book.length == 1
                  ? CustomDraggable(
                      key: topLevelKey,
                      data: book.first,
                      child: BookFolder(books: book),
                    )
                  : BookFolder(key: topLevelKey, books: book);
            }),
          ],
          builder: (children) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    HintBanner(
                      icon: const Icon(Icons.copy),
                      hintKey: HintKey.dragAndDropToCreateFolder,
                      margin: AppBookshelfTokens.hintMargin,
                      child: Text(
                        L10n.of(context).dragAndDropToCreateFolderHint,
                      ),
                    ),
                    Expanded(
                      child: GridView(
                        key: _gridViewKey,
                        controller: _scrollController,
                        padding: AppBookshelfTokens.gridPadding,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: max(
                            1,
                            constraints.maxWidth ~/ Prefs().bookCoverWidth,
                          ),
                          childAspectRatio: AppBookshelfTokens.gridAspectRatio,
                          mainAxisSpacing: AppBookshelfTokens.gridMainSpacing,
                          crossAxisSpacing: AppBookshelfTokens.gridCrossSpacing,
                        ),
                        children: children,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    final body = Column(
      children: [
        buildFilterBar(),
        Expanded(
          child: DropTarget(
            onDragDone: (detail) async {
              if (_importing) return;
              setState(() {
                _dragging = false;
                _importing = true;
              });
              try {
                final files = <File>[];
                for (final file in detail.files) {
                  files.add(
                    await _copyToTempFile(
                      sourcePath: file.path,
                      fileName: file.name,
                    ),
                  );
                }
                await _importFiles(files);
              } catch (_) {
                if (mounted) AppFeedback.showError(this.context);
              } finally {
                _dragging = false;
                _importing = false;
                if (mounted) setState(() {});
              }
            },
            onDragEntered: (detail) => setState(() => _dragging = true),
            onDragExited: (detail) => setState(() => _dragging = false),
            child: Stack(
              children: [
                buildBookshelfBody,
                if (_dragging)
                  Container(
                    color: Theme.of(context).colorScheme.surface.withAlpha(90),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            EvaIcons.arrowhead_down_outline,
                            size: AppBookshelfTokens.dragIconSize,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          Text(
                            L10n.of(context).bookshelfDragging,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    final appBar = AppBar(
      forceMaterialTransparency: true,
      title: Container(
        height: AppBookshelfTokens.searchHeight,
        constraints: const BoxConstraints(
          maxWidth: AppBookshelfTokens.searchMaxWidth,
        ),
        child: AppCard(
          margin: AppSpacing.zero,
          padding: AppBookshelfTokens.searchPadding,
          borderRadius: AppRadius.pill,
          semanticLabel: L10n.of(context).searchBooksOrNotes,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            );
          },
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Text(
                  L10n.of(context).searchBooksOrNotes,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        widget.syncButton ?? const SyncButton(),
        AppIconButton(
          icon: Icons.add,
          semanticLabel: L10n.of(context).tagAddButton,
          tooltip: L10n.of(context).tagAddButton,
          isLoading: _importing,
          onPressed: _importBook,
        ),
        AppIconButton(
          icon: Icons.sort,
          semanticLabel: L10n.of(context).bookshelfSort,
          tooltip: L10n.of(context).bookshelfSort,
          onPressed: () {
            showMenu(
              context: context,
              position: RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0,
                0,
              ),
              items: [
                for (final sortField in SortFieldEnum.values)
                  PopupMenuItem(
                    onTap: () {
                      Prefs().sortField = sortField;
                      ref.read(bookListProvider.notifier).refresh();
                    },
                    child: Text(
                      sortField.getL10n(context),
                      style: TextStyle(
                        color: sortField == Prefs().sortField
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                PopupMenuItem(
                  enabled: false,
                  child: StatefulBuilder(
                    builder: (_, setStateMenu) => Row(
                      children: [
                        Expanded(
                          child: AnxSegmentedButton<SortOrderEnum>(
                            onSelectionChanged: (value) {
                              Prefs().sortOrder = value.first;
                              ref.read(bookListProvider.notifier).refresh();
                              setStateMenu(() {});
                            },
                            segments: SortOrderEnum.values
                                .map(
                                  (order) => SegmentButtonItem(
                                    value: order,
                                    label: order.getL10n(
                                      navigatorKey.currentContext!,
                                    ),
                                  ),
                                )
                                .toList(),
                            selected: {Prefs().sortOrder},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );

    return Container(
      decoration: Prefs().eInkMode
          ? null
          : BoxDecoration(
              gradient: RadialGradient(
                tileMode: TileMode.clamp,
                center: Alignment.topRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withAlpha(5),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
      child: Scaffold(
        backgroundColor: AppColors.transparent,
        appBar: appBar,
        body: AppSafeArea(top: false, child: body),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppBookshelfTokens.filterChipTrailing,
      child: FilterChip(
        labelPadding: AppBookshelfTokens.filterChipLabelPadding,
        padding: AppBookshelfTokens.filterChipPadding,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        checkmarkColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
