import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/service/notes/export_notes.dart';
import 'package:anx_reader/service/notes/import_notes.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

typedef BookNotesExporter = Future<void> Function(
  Book book,
  List<BookNote> notes,
  ExportType type, {
  bool mergeChapterHeadings,
});

class BookNotesPage extends ConsumerStatefulWidget {
  const BookNotesPage({
    super.key,
    required this.book,
    required this.numberOfNotes,
    required this.isMobile,
    this.notesExporter,
  });

  final Book book;
  final int numberOfNotes;
  final bool isMobile;
  final BookNotesExporter? notesExporter;

  @override
  ConsumerState<BookNotesPage> createState() => _BookNotesPageState();
}

class _BookNotesPageState extends ConsumerState<BookNotesPage> {
  Widget bookInfo(BuildContext context, Book book, int numberOfNotes) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall!.copyWith(
          fontWeight: FontWeight.bold,
          overflow: TextOverflow.ellipsis,
          fontFamily: 'SourceHanSerif',
        );
    return AppCard(
      padding: AppNotesTokens.infoPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > AppNotesTokens.infoWideBreakpoint) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title, style: titleStyle, maxLines: 1),
                      notesStatistic(context, numberOfNotes, book),
                      SizedBox(height: AppNotesTokens.infoActionSpacing),
                      operators(context, book),
                    ],
                  ),
                ),
                SizedBox(width: AppNotesTokens.infoCoverSpacing),
                Hero(
                  tag: book.coverFullPath,
                  child: BookCover(
                    book: book,
                    height: AppNotesTokens.infoCoverHeight,
                    width: AppNotesTokens.infoCoverWidth,
                    radius: AppNotesTokens.infoCoverRadius,
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title, style: titleStyle, maxLines: 2),
                        notesStatistic(context, numberOfNotes, book),
                        SizedBox(height: AppNotesTokens.infoActionSpacing),
                      ],
                    ),
                  ),
                  SizedBox(width: AppNotesTokens.infoCoverSpacing),
                  Hero(
                    tag: book.coverFullPath,
                    child: BookCover(
                      book: book,
                      height: AppNotesTokens.infoCoverHeight,
                      width: AppNotesTokens.infoCoverWidth,
                      radius: AppNotesTokens.infoCoverRadius,
                    ),
                  ),
                ],
              ),
              operators(context, book),
            ],
          );
        },
      ),
    );
  }

  Future<void> handleExportNotes(BuildContext context, Book book,
      {List<BookNote>? notes}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var mergeChapters = Prefs().notesExportMergeChapters;
        ExportType? pendingType;
        ExportType? lastAttemptType;
        var exportFailed = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Consumer(
              builder: (context, ref, _) {
                final asyncState = ref.watch(bookNotesControllerProvider(book));
                Future<void> runExport(ExportType type) async {
                  if (pendingType != null) return;
                  final allowMerge =
                      asyncState.valueOrNull?.exportSortMode.field ==
                          NotesSortField.cfi;
                  final shouldMerge = allowMerge && mergeChapters;
                  setModalState(() {
                    pendingType = type;
                    lastAttemptType = type;
                    exportFailed = false;
                  });
                  try {
                    final controller =
                        ref.read(bookNotesControllerProvider(book).notifier);
                    final sorted = controller.notesForExport(
                      selectedOnly: false,
                      custom: notes,
                    );
                    await (widget.notesExporter ?? exportNotes)(
                      book,
                      sorted,
                      type,
                      mergeChapterHeadings:
                          type == ExportType.csv || type == ExportType.json
                              ? false
                              : shouldMerge,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (_) {
                    if (context.mounted) {
                      setModalState(() => exportFailed = true);
                    }
                  } finally {
                    if (context.mounted) {
                      setModalState(() => pendingType = null);
                    }
                  }
                }

                return PopScope(
                  canPop: pendingType == null,
                  child: AppSafeArea(
                    top: false,
                    child: asyncState.when(
                      data: (state) {
                        return SingleChildScrollView(
                          padding: AppNotesTokens.exportPadding,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _exportSortControls(
                                context,
                                ref,
                                state,
                                mergeChapters: mergeChapters,
                                onMergeChanged: pendingType == null
                                    ? (value) {
                                        setModalState(() {
                                          mergeChapters = value;
                                        });
                                        Prefs().notesExportMergeChapters =
                                            value;
                                      }
                                    : null,
                              ),
                              SizedBox(
                                height: AppNotesTokens.exportSectionSpacing,
                              ),
                              if (exportFailed && lastAttemptType != null)
                                Padding(
                                  padding: AppSpacing.only(
                                    bottom: AppSpacing.tokens.s12,
                                  ),
                                  child: AppInlineFeedback(
                                    onRetry: () => runExport(lastAttemptType!),
                                  ),
                                ),
                              Wrap(
                                spacing: AppSpacing.tokens.s8,
                                runSpacing: AppSpacing.tokens.s8,
                                children: [
                                  _exportButton(
                                    ExportType.copy,
                                    label: 'Copy',
                                    icon: Icons.copy,
                                    pendingType: pendingType,
                                    onPressed: () => runExport(ExportType.copy),
                                  ),
                                  _exportButton(
                                    ExportType.md,
                                    label: 'Markdown',
                                    icon: IonIcons.logo_markdown,
                                    pendingType: pendingType,
                                    onPressed: () => runExport(ExportType.md),
                                  ),
                                  _exportButton(
                                    ExportType.txt,
                                    label: 'Text',
                                    icon: Icons.text_snippet,
                                    pendingType: pendingType,
                                    onPressed: () => runExport(ExportType.txt),
                                  ),
                                  _exportButton(
                                    ExportType.csv,
                                    label: 'CSV',
                                    icon: Icons.table_chart,
                                    pendingType: pendingType,
                                    onPressed: () => runExport(ExportType.csv),
                                  ),
                                  _exportButton(
                                    ExportType.json,
                                    label: 'JSON',
                                    icon: Icons.data_object,
                                    pendingType: pendingType,
                                    onPressed: () => runExport(ExportType.json),
                                  ),
                                ],
                              ),
                              SizedBox(
                                  height: AppNotesTokens.exportHintSpacing),
                              Text(
                                L10n.of(context).notesJsonExportHint,
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                      loading: () => const SizedBox(
                        height: AppNotesTokens.exportLoadingHeight,
                        child: Center(child: AppLoadingIndicator()),
                      ),
                      error: (error, stack) => AppErrorState(
                        onRetry: () async {
                          ref.invalidate(bookNotesControllerProvider(book));
                          await ref
                              .read(bookNotesControllerProvider(book).future);
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _exportSortControls(
    BuildContext context,
    WidgetRef ref,
    BookNotesState state, {
    required bool mergeChapters,
    required ValueChanged<bool>? onMergeChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.of(context).notesPageExport,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: AppNotesTokens.exportHintSpacing),
        Wrap(
          children: [
            _exportSortButton(
              context: context,
              label: L10n.of(context).notesPageSortTime,
              field: NotesSortField.createdTime,
              current: state.exportSortMode,
              onPressed: () {
                if (state.exportSortMode.field == NotesSortField.createdTime) {
                  ref
                      .read(bookNotesControllerProvider(widget.book).notifier)
                      .toggleExportSortDirection();
                } else {
                  ref
                      .read(bookNotesControllerProvider(widget.book).notifier)
                      .setExportSortField(NotesSortField.createdTime);
                }
              },
            ),
            _exportSortButton(
              context: context,
              label: L10n.of(context).notesPageSortChapter,
              field: NotesSortField.cfi,
              current: state.exportSortMode,
              onPressed: () {
                if (state.exportSortMode.field == NotesSortField.cfi) {
                  ref
                      .read(bookNotesControllerProvider(widget.book).notifier)
                      .toggleExportSortDirection();
                } else {
                  ref
                      .read(bookNotesControllerProvider(widget.book).notifier)
                      .setExportSortField(NotesSortField.cfi);
                }
              },
            ),
          ],
        ),
        if (state.exportSortMode.field == NotesSortField.cfi)
          Padding(
            padding: AppNotesTokens.exportMergePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.of(context).notesExportMergeChapters,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    Switch(
                      value: mergeChapters,
                      onChanged: onMergeChanged,
                    ),
                  ],
                ),
                Text(
                  L10n.of(context).notesExportMergeChaptersDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _exportSortButton({
    required BuildContext context,
    required String label,
    required NotesSortField field,
    required NotesSortMode current,
    required VoidCallback onPressed,
  }) {
    final isActive = current.field == field;
    return Padding(
      padding: AppNotesTokens.exportSortPadding,
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

  Widget _exportButton(
    ExportType type, {
    required String label,
    required IconData icon,
    required ExportType? pendingType,
    required VoidCallback onPressed,
  }) {
    return AppButton(
      label: label,
      icon: icon,
      variant: AppButtonVariant.outlined,
      isLoading: pendingType == type,
      enabled: pendingType == null,
      onPressed: onPressed,
    );
  }

  Wrap operators(BuildContext context, Book book) {
    return Wrap(
      spacing: AppSpacing.tokens.s8,
      runSpacing: AppSpacing.tokens.s8,
      children: [
        AppButton(
          icon: Icons.details,
          label: L10n.of(context).notesPageDetail,
          variant: AppButtonVariant.text,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BookDetail(book: book),
              ),
            );
          },
        ),
        AppButton(
          icon: Icons.ios_share,
          label: L10n.of(context).notesPageExport,
          variant: AppButtonVariant.text,
          onPressed: () => handleExportNotes(context, book),
        ),
        AppButton(
          icon: Icons.file_download_outlined,
          label: L10n.of(context).notesJsonImport,
          variant: AppButtonVariant.text,
          onPressed: () async {
            final imported = await importNotesJsonForBook(context, book);
            if (imported != null && imported > 0 && mounted) {
              await ref
                  .read(bookNotesControllerProvider(book).notifier)
                  .refresh();
            }
          },
        ),
      ],
    );
  }

  Widget notesStatistic(BuildContext context, int numberOfNotes, Book book) {
    final digitStyle = Theme.of(context).textTheme.displaySmall!;
    final textStyle = Theme.of(context)
        .textTheme
        .titleMedium!
        .copyWith(fontFamily: 'SourceHanSerif');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        highlightDigit(
          context,
          L10n.of(context).notesNotes(numberOfNotes),
          textStyle,
          digitStyle,
        ),
        Text(
          L10n.of(context).notesReadPercentage(
            '${(book.readingPercentage * 100).toStringAsFixed(2)}%',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isMobile ? AppBar(title: Text(widget.book.title)) : null,
      extendBodyBehindAppBar: true,
      body: AppSafeArea(
        bottom: false,
        child: ListView(
          padding: AppNotesTokens.pagePadding,
          children: [
            bookInfo(context, widget.book, widget.numberOfNotes),
            SizedBox(height: AppNotesTokens.pageContentSpacing),
            BookNotesList(
              book: widget.book,
              reading: false,
              exportNotes: handleExportNotes,
            ),
          ],
        ),
      ),
    );
  }
}
