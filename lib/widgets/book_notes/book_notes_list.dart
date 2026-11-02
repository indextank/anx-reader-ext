import 'package:anx_reader/constants/note_annotations.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/book_notes/book_note_tile.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_service.dart';
import 'package:anx_reader/widgets/hint/hint_banner.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:sticky_headers/sticky_headers.dart';

class BookNotesList extends ConsumerWidget {
  const BookNotesList({
    super.key,
    required this.book,
    required this.reading,
    this.exportNotes,
  });

  final Book book;
  final bool reading;
  final void Function(BuildContext context, Book book, {List<BookNote>? notes})?
      exportNotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(bookNotesControllerProvider(book));
    return notesAsync.when(
      data: (state) => _buildContent(context, ref, state),
      loading: () => const Padding(
        padding: AppBookNotesTokens.loadingPadding,
        child: Center(child: AppLoadingIndicator()),
      ),
      error: (error, stack) => AppErrorState(
        onRetry: () async {
          ref.invalidate(bookNotesControllerProvider(book));
          await ref.read(bookNotesControllerProvider(book).future);
        },
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, BookNotesState state) {
    return Column(
      children: [
        StickyHeader(
          header: _header(context, ref, state),
          content: state.visibleNotes.isEmpty
              ? const Column(
                  children: [
                    Divider(),
                    NotesTips(),
                  ],
                )
              : Column(
                  children: [
                    HintBanner(
                      icon: const Icon(Icons.info_outline),
                      hintKey: HintKey.bookNotesOperations,
                      margin: AppBookNotesTokens.hintMargin,
                      child: Text(L10n.of(context).bookNotesOperationsHint),
                    ),
                    ...state.visibleNotes.map(
                      (bookNote) => _slidableNote(
                        context,
                        ref,
                        bookNote,
                        _bookNoteItem(context, ref, state, bookNote),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, BookNotesState state) {
    final notifier = ref.read(bookNotesControllerProvider(book).notifier);
    final buttonColor = Theme.of(context).colorScheme.primary;
    if (state.isSelecting) {
      final allSelected =
          state.selectedNoteIds.length == state.visibleNotes.length &&
              state.visibleNotes.isNotEmpty;
      return Row(
        children: [
          AppIconButton(
            semanticLabel:
                L10n.of(context).notesNotes(state.selectedNotes.length),
            child: Icon(
              allSelected ? EvaIcons.checkmark_circle : Icons.circle_outlined,
              color: buttonColor,
            ),
            onPressed: () {
              if (allSelected) {
                notifier.clearSelection();
              } else {
                notifier.selectAllVisible();
              }
            },
          ),
          const Spacer(),
          AppIconButton(
            icon: EvaIcons.trash_2,
            tooltip: L10n.of(context).commonDelete,
            onPressed: () {
              AppDialog.confirm(
                context,
                title: L10n.of(context).commonDelete,
                message:
                    L10n.of(context).notesNotes(state.selectedNotes.length),
                isDangerous: true,
                dangerDescription: L10n.of(context).bookNotesOperationsHint,
                onConfirm: () async {
                  final notesToDelete =
                      List<BookNote>.from(state.selectedNotes);
                  await notifier.deleteNotes(notesToDelete);
                  if (reading) {
                    final player = epubPlayerKey.currentState;
                    if (player != null) {
                      for (final note in notesToDelete) {
                        if (note.cfi.isNotEmpty) {
                          player.removeAnnotation(note.cfi);
                        }
                      }
                    }
                  }
                },
              );
            },
          ),
          if (!reading && exportNotes != null)
            AppIconButton(
              icon: Icons.ios_share,
              tooltip: L10n.of(context).notesPageExport,
              onPressed: () {
                final selected = notifier.notesForExport(selectedOnly: true);
                exportNotes!.call(context, book, notes: selected);
              },
            ),
        ],
      );
    }

    return Row(
      children: [
        const Spacer(),
        AppIconButton(
          semanticLabel: L10n.of(context).bookNotesOperationsHint,
          icon: state.showAllNotes ? EvaIcons.funnel_outline : EvaIcons.funnel,
          onPressed: () => _showFilterSheet(context, ref),
        ),
      ],
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final asyncState = ref.watch(bookNotesControllerProvider(book));
            return AppSafeArea(
              top: false,
              child: asyncState.when(
                data: (state) => SingleChildScrollView(
                  padding: AppBookNotesTokens.filterPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        children: [
                          _sortButton(
                            context: context,
                            label: L10n.of(context).notesPageSortTime,
                            field: NotesSortField.createdTime,
                            current: state.viewSortMode,
                            onPressed: () => ref
                                .read(
                                    bookNotesControllerProvider(book).notifier)
                                .toggleViewSort(NotesSortField.createdTime),
                          ),
                          _sortButton(
                            context: context,
                            label: L10n.of(context).notesPageSortChapter,
                            field: NotesSortField.cfi,
                            current: state.viewSortMode,
                            onPressed: () => ref
                                .read(
                                    bookNotesControllerProvider(book).notifier)
                                .toggleViewSort(NotesSortField.cfi),
                          ),
                        ],
                      ),
                      AppButton(
                        label: L10n.of(context).noteListShowBookmark,
                        icon: state.showBookmarks
                            ? EvaIcons.bookmark
                            : EvaIcons.bookmark_outline,
                        variant: AppButtonVariant.outlined,
                        onPressed: () => ref
                            .read(bookNotesControllerProvider(book).notifier)
                            .toggleShowBookmarks(),
                      ),
                      for (final type in notesType)
                        _filterRow(context, ref, state, type),
                      const Divider(),
                      AppButton(
                        label: L10n.of(context).notesPageFilterReset,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => ref
                            .read(bookNotesControllerProvider(book).notifier)
                            .resetFilters(),
                      ),
                      SizedBox(height: AppSpacing.tokens.s8),
                      AppButton(
                        label: L10n.of(context)
                            .notesPageViewAllNNotes(state.visibleNotes.length),
                        onPressed: Navigator.of(context).pop,
                      ),
                    ],
                  ),
                ),
                loading: () => const SizedBox(
                  height: AppBookNotesTokens.filterLoadingHeight,
                  child: Center(child: AppLoadingIndicator()),
                ),
                error: (error, stack) => AppErrorState(
                  onRetry: () async {
                    ref.invalidate(bookNotesControllerProvider(book));
                    await ref.read(bookNotesControllerProvider(book).future);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sortButton({
    required BuildContext context,
    required String label,
    required NotesSortField field,
    required NotesSortMode current,
    required VoidCallback onPressed,
  }) {
    final isActive = current.field == field;
    return Padding(
      padding: AppBookNotesTokens.sortPadding,
      child: AppButton(
        label: label,
        icon: isActive
            ? (current.direction == SortDirection.asc
                ? EvaIcons.arrow_up
                : EvaIcons.arrow_down)
            : null,
        variant:
            isActive ? AppButtonVariant.primary : AppButtonVariant.outlined,
        onPressed: onPressed,
      ),
    );
  }

  Widget _filterRow(
    BuildContext context,
    WidgetRef ref,
    BookNotesState state,
    NoteTypeOption type,
  ) {
    final notifier = ref.read(bookNotesControllerProvider(book).notifier);

    Widget colorButton(String color) {
      final key = '${type.type}#$color';
      final selected = state.enabledTypeColors.contains(key);
      return AppIconButton(
        semanticLabel: color,
        child: Icon(
          selected ? EvaIcons.checkmark_circle_2 : Icons.circle,
          color: AppBookNotesTokens.filterColor(color),
          size: AppBookNotesTokens.filterIconSize,
        ),
        onPressed: () => notifier.toggleTypeColor(type.type, color),
      );
    }

    return Padding(
      padding: AppBookNotesTokens.filterRowPadding,
      child: Row(
        children: [
          AppIconButton(
            semanticLabel: type.type,
            icon: type.icon,
            onPressed: () => notifier.toggleTypeColors(type.type),
          ),
          const Spacer(),
          for (final color in notesColors) colorButton(color),
        ],
      ),
    );
  }

  Widget _bookNoteItem(
    BuildContext context,
    WidgetRef ref,
    BookNotesState state,
    BookNote bookNote,
  ) {
    final notifier = ref.read(bookNotesControllerProvider(book).notifier);
    return BookNoteTile(
      note: bookNote,
      onTap: () {
        if (state.isSelecting) {
          notifier.toggleSelection(bookNote);
        } else {
          if (reading) {
            epubPlayerKey.currentState?.goToCfi(bookNote.cfi);
          } else {
            pushToReadingPage(ref, context, book, cfi: bookNote.cfi);
          }
        }
      },
      onLongPress: () {
        notifier.toggleSelection(bookNote);
      },
      trailing: state.isSelecting
          ? AppIconButton(
              semanticLabel: bookNote.content,
              child: Icon(
                state.selectedNoteIds.contains(bookNote.id)
                    ? EvaIcons.checkmark_circle
                    : Icons.circle_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => notifier.toggleSelection(bookNote),
            )
          : null,
    );
  }

  Widget _slidableNote(
    BuildContext context,
    WidgetRef ref,
    BookNote bookNote,
    Widget child,
  ) {
    return Slidable(
      key: ValueKey(bookNote.id),
      startActionPane: _actionPane(context, ref, bookNote),
      endActionPane: _actionPane(context, ref, bookNote),
      child: child,
    );
  }

  ActionPane _actionPane(
      BuildContext context, WidgetRef ref, BookNote bookNote) {
    return ActionPane(
      motion: const StretchMotion(),
      children: [
        SlidableAction(
          onPressed: (context) {
            ExcerptShareService.showShareExcerpt(
              context: context,
              bookTitle: book.title,
              author: book.author,
              excerpt: bookNote.content,
              chapter: bookNote.chapter,
            );
          },
          icon: Icons.share,
          label: L10n.of(context).readingPageShareShare,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        SlidableAction(
          onPressed: (context) => _editBookNote(context, ref, bookNote),
          icon: Icons.edit,
          label: L10n.of(context).commonEdit,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
      ],
    );
  }

  void _editBookNote(BuildContext context, WidgetRef ref, BookNote bookNote) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BookNoteEditDialog(
        bookNote: bookNote,
        onUpdate:
            ref.read(bookNotesControllerProvider(book).notifier).updateNote,
      ),
    );
  }
}

class _BookNoteEditDialog extends StatefulWidget {
  const _BookNoteEditDialog({
    required this.bookNote,
    required this.onUpdate,
  });

  final BookNote bookNote;
  final Future<void> Function(BookNote note) onUpdate;

  @override
  State<_BookNoteEditDialog> createState() => _BookNoteEditDialogState();
}

class _BookNoteEditDialogState extends State<_BookNoteEditDialog> {
  late String _currentType = widget.bookNote.type;
  late String _currentColor = widget.bookNote.color;
  late final _noteController = TextEditingController(
    text: widget.bookNote.readerNote,
  );
  late final _contentController = TextEditingController(
    text: widget.bookNote.content,
  );
  bool _isEditingContent = false;
  bool _pending = false;
  bool _showError = false;

  @override
  void dispose() {
    _noteController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending) return;
    final note = BookNote(
      id: widget.bookNote.id,
      bookId: widget.bookNote.bookId,
      content: _contentController.text.trim(),
      cfi: widget.bookNote.cfi,
      chapter: widget.bookNote.chapter,
      type: _currentType,
      color: _currentColor,
      readerNote: _noteController.text.trim(),
      createTime: widget.bookNote.createTime,
      updateTime: DateTime.now(),
    );
    setState(() {
      _pending = true;
      _showError = false;
    });
    try {
      await widget.onUpdate(note);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_pending,
      child: AppDialog(
        title: l10n.commonEdit,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: AppBookNotesTokens.editContentPadding,
                child: _isEditingContent
                    ? AppTextField(
                        controller: _contentController,
                        hintText: l10n.contextMenuAddNoteTips,
                        enabled: !_pending,
                        maxLines: 3,
                      )
                    : AppCard(
                        semanticLabel: l10n.commonEdit,
                        onTap: () => setState(() => _isEditingContent = true),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            widget.bookNote.content,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...notesType.map(
                      (type) => AppIconButton(
                        semanticLabel: type.type,
                        enabled: !_pending,
                        onPressed: () =>
                            setState(() => _currentType = type.type),
                        child: Icon(
                          type.icon,
                          color: _currentType == type.type
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ...notesColors.map(
                      (color) => AppIconButton(
                        semanticLabel: color,
                        enabled: !_pending,
                        onPressed: () => setState(() => _currentColor = color),
                        child: Icon(
                          _currentColor == color
                              ? EvaIcons.checkmark_circle_2
                              : Icons.circle,
                          color: AppBookNotesTokens.filterColor(color),
                          size: AppBookNotesTokens.editColorIconSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: AppBookNotesTokens.editNotePadding,
                child: AppTextField(
                  controller: _noteController,
                  hintText: l10n.contextMenuAddNoteTips,
                  enabled: !_pending,
                  maxLines: 3,
                ),
              ),
              if (_showError) ...[
                SizedBox(height: AppSpacing.tokens.s8),
                AppInlineFeedback(onRetry: _save),
              ],
            ],
          ),
        ),
        actions: [
          AppButton(
            label: l10n.commonCancel,
            variant: AppButtonVariant.text,
            enabled: !_pending,
            onPressed: () => Navigator.pop(context),
          ),
          AppButton(
            label: l10n.commonSave,
            isLoading: _pending,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
