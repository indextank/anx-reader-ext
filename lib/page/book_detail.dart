import 'dart:io';
import 'dart:ui';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/color/hash_color.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/common/color_picker_sheet.dart';
import 'package:anx_reader/widgets/common/tag_chip.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/hint/hint_banner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

class BookDetail extends ConsumerStatefulWidget {
  const BookDetail({
    super.key,
    required this.book,
    this.totalReadingTimeLoader,
    this.readingTimeLoader,
    this.bookSaver,
    this.coverWriter,
  });

  final Book book;
  final Future<int> Function(int bookId)? totalReadingTimeLoader;
  final Future<List<ReadingTime>> Function(int bookId)? readingTimeLoader;
  final Future<void> Function(Book book)? bookSaver;
  final Future<void> Function(File image, String fullPath)? coverWriter;

  @override
  ConsumerState<BookDetail> createState() => _BookDetailState();
}

class _BookDetailState extends ConsumerState<BookDetail> {
  late double rating;
  bool isEditing = false;
  late Book _book;
  bool _isCollapsed = false;
  final TextEditingController _newTagController = TextEditingController();
  Color? _pendingTagColor;
  bool _creatingTag = false;
  bool _tagCreateFailed = false;

  String get _bookFileFormat {
    final extension = path.extension(_book.filePath).replaceFirst('.', '');
    if (extension.isEmpty) {
      return '-';
    }
    return extension.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    rating = widget.book.rating;
    _book = widget.book;
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _createTag() async {
    if (_creatingTag) return;
    final value = _newTagController.text.trim();
    if (value.isEmpty) return;
    final color = _pendingTagColor ?? hashColor(value);
    setState(() {
      _creatingTag = true;
      _tagCreateFailed = false;
    });
    try {
      await ref
          .read(bookTagEditorProvider(widget.book.id).notifier)
          .createAndAttach(value, color: color);
      if (!mounted) return;
      ref.read(bookListProvider.notifier).refresh();
      _newTagController.clear();
      _pendingTagColor = null;
    } catch (_) {
      if (mounted) setState(() => _tagCreateFailed = true);
    } finally {
      if (mounted) setState(() => _creatingTag = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildBackground() {
      final surface = Theme.of(context).colorScheme.surface;
      final bg = ShaderMask(
        shaderCallback: (rect) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              surface.withAlpha(AppBookDetailTokens.backgroundAlphaHigh),
              surface.withAlpha(AppBookDetailTokens.backgroundAlphaMedium),
              surface.withAlpha(AppBookDetailTokens.backgroundAlphaLow),
            ],
          ).createShader(
            Rect.fromLTRB(0, 0, rect.width, rect.height),
          );
        },
        blendMode: BlendMode.dstATop,
        child: BookCover(
          book: _book,
          height: MediaQuery.of(context).size.height *
              AppBookDetailTokens.backgroundHeightFactor,
          width: MediaQuery.of(context).size.width,
        ),
      );
      return Transform.scale(
        scale: AppBookDetailTokens.backgroundScale,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: AppBookDetailTokens.backgroundBlur,
            sigmaY: AppBookDetailTokens.backgroundBlur,
          ),
          child: bg,
        ),
      );
    }

    Widget buildBookBaseDetail(double width) {
      final bookTitleStyle =
          Theme.of(context).textTheme.headlineSmall!.copyWith(
                fontFamily: 'SourceHanSerif',
                fontWeight: FontWeight.bold,
              );
      final bookAuthorStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
            fontFamily: 'SourceHanSerif',
          );
      const top = AppBookDetailTokens.baseTop;

      return SizedBox(
        height: AppBookDetailTokens.baseContentHeight + top,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: AppBookDetailTokens.baseCardTop + top,
              child: SizedBox(
                height: AppBookDetailTokens.baseCardHeight,
                width: width,
                child: AppCard(
                  margin: AppBookDetailTokens.baseCardMargin,
                  child: Row(
                    children: [
                      const Spacer(),
                      Stack(
                        children: [
                          Container(
                            padding: AppBookDetailTokens.progressPadding,
                            width: AppBookDetailTokens.progressSize,
                            height: AppBookDetailTokens.progressSize,
                            child: CircularProgressIndicator(
                              value: widget.book.readingPercentage,
                              strokeWidth: AppBookDetailTokens.progressStroke,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Center(
                              child: Text(
                                '${(widget.book.readingPercentage * 100).toStringAsFixed(0)}%',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppBookDetailTokens.coverLeft,
              top: top,
              child: GestureDetector(
                onTap: () async {
                  if (!isEditing) {
                    return;
                  }

                  FilePickerResult? result;
                  try {
                    result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      allowMultiple: false,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    AppFeedback.showError(
                      context,
                      message: L10n.of(context).filePickerFailed(e.toString()),
                    );
                    return;
                  }

                  if (!mounted || result == null) return;

                  final image = File(result.files.single.path!);

                  AnxLog.info('BookDetail: Image path: ${image.path}');
                  final oldCoverImageFile = File(widget.book.coverFullPath);
                  final oldCoverExists = await oldCoverImageFile.exists();
                  if (!mounted) return;
                  if (oldCoverExists) {
                    await oldCoverImageFile.delete();
                    if (!mounted) return;
                  }

                  String oldName = widget.book.coverPath
                      .split('-')
                      .sublist(0, widget.book.coverPath.split('-').length - 1)
                      .join('');
                  if (!oldName.startsWith('cover/')) {
                    oldName = 'cover/$oldName';
                  }

                  final newPath =
                      '$oldName-${DateTime.now().millisecondsSinceEpoch.toString()}.png'
                          .trim();

                  AnxLog.info('BookDetail: New path: $newPath');
                  final newFullPath = getBasePath(newPath);
                  await (widget.coverWriter ??
                      (image, fullPath) async {
                        await File(fullPath)
                            .writeAsBytes(await image.readAsBytes());
                      })(image, newFullPath);
                  if (!mounted) return;
                  widget.book.coverPath = newPath;

                  setState(() {
                    widget.book.coverPath = newPath;
                    bookDao.updateBook(widget.book);
                    Sync().syncData(SyncDirection.upload, ref,
                        trigger: SyncTrigger.auto);
                    ref.read(bookListProvider.notifier).refresh();
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.border12,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .shadow
                            .withAlpha(AppBookDetailTokens.coverShadowAlpha),
                        spreadRadius: AppBookDetailTokens.coverShadowSpread,
                        blurRadius: AppBookDetailTokens.coverShadowBlur,
                        offset: AppBookDetailTokens.coverShadowOffset,
                      ),
                    ],
                  ),
                  child: Hero(
                    tag: widget.book.coverFullPath,
                    child: BookCover(
                      book: widget.book,
                      height: AppBookDetailTokens.coverHeight,
                      width: AppBookDetailTokens.coverWidth,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppBookDetailTokens.ratingLeft,
              top: AppBookDetailTokens.ratingTop + top,
              child: RatingBar.builder(
                initialRating: rating,
                minRating: 0,
                direction: Axis.horizontal,
                allowHalfRating: true,
                itemCount: 5,
                itemSize: AppBookDetailTokens.ratingItemSize,
                itemPadding: AppBookDetailTokens.ratingItemPadding,
                itemBuilder: (context, _) => Icon(
                  Icons.star,
                  color: context.appTheme.colors.warning,
                ),
                onRatingUpdate: (rating) {
                  setState(() {
                    this.rating = rating;
                    updateBookRating(widget.book, rating);
                  });
                },
              ),
            ),
            Positioned(
              left: AppBookDetailTokens.titleLeft,
              top: AppBookDetailTokens.titleTop + top,
              child: SizedBox(
                width: width - AppBookDetailTokens.titleLeft,
                height: AppBookDetailTokens.titleHeight,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        autofocus: true,
                        initialValue: widget.book.title,
                        enabled: isEditing,
                        style: bookTitleStyle,
                        maxLines: null,
                        minLines: 1,
                        border: InputBorder.none,
                        contentPadding: AppSpacing.zero,
                        isCollapsed: true,
                        onChanged: (value) {
                          widget.book.title = value.replaceAll('\n', ' ');
                        },
                      ),
                      SizedBox(height: AppBookDetailTokens.titleSpacing),
                      AppTextField(
                        initialValue: widget.book.author,
                        enabled: isEditing,
                        style: bookAuthorStyle,
                        maxLines: null,
                        minLines: 1,
                        border: InputBorder.none,
                        contentPadding: AppSpacing.zero,
                        isCollapsed: true,
                        onChanged: (value) {
                          widget.book.author = value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildEditButton() {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: HintBanner(
              hintKey: HintKey.editBookDetails,
              margin: AppBookDetailTokens.editHintMargin,
              child: Text(L10n.of(context).bookDetailEditHint),
            ),
          ),
          isEditing
              ? AppSubmitButton(
                  label: L10n.of(context).bookDetailSave,
                  icon: Icons.save,
                  variant: AppButtonVariant.outlined,
                  onSubmit: () async {
                    await (widget.bookSaver ?? bookDao.updateBook)(widget.book);
                    if (!mounted) return;
                    setState(() => isEditing = false);
                    Sync().syncData(
                      SyncDirection.upload,
                      ref,
                      trigger: SyncTrigger.manual,
                    );
                    ref.read(bookListProvider.notifier).refresh();
                  },
                )
              : AppButton(
                  label: L10n.of(context).bookDetailEdit,
                  icon: Icons.edit,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => setState(() => isEditing = true),
                ),
        ],
      );
    }

    Widget buildBookStatistics() {
      final textStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
      final digitStyle = Theme.of(context).textTheme.displaySmall!;

      Widget buildNthBooksItem() {
        return Padding(
          padding: AppBookDetailTokens.statisticsItemPadding,
          child: highlightDigit(
            context,
            L10n.of(context).bookDetailNthBook(widget.book.id),
            textStyle,
            digitStyle,
          ),
        );
      }

      Widget buildRankItem() {
        return Padding(
          padding: AppBookDetailTokens.statisticsItemPadding,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(text: rating.toString(), style: digitStyle),
                TextSpan(text: ' / 5', style: textStyle),
              ],
            ),
          ),
        );
      }

      Widget buildReadingTimeItem() {
        return FutureBuilder<int>(
          future: widget.totalReadingTimeLoader?.call(widget.book.id) ??
              readingTimeDao.selectTotalReadingTimeByBookId(widget.book.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SizedBox(
                width: MediaQuery.of(context).size.width,
                child: AppInlineFeedback(
                  message: L10n.of(context).commonLoadFailed,
                  onRetry: () async {
                    if (mounted) setState(() {});
                  },
                ),
              );
            }
            if (snapshot.hasData) {
              final totalReadingTime = snapshot.data!;
              final hours = totalReadingTime ~/ 3600;
              final minutes = totalReadingTime % 3600 ~/ 60;
              return Padding(
                padding: AppBookDetailTokens.statisticsItemPadding,
                child: Row(
                  children: [
                    highlightDigit(
                      context,
                      L10n.of(context).commonHours(hours),
                      textStyle,
                      digitStyle,
                    ),
                    highlightDigit(
                      context,
                      L10n.of(context).commonMinutes(minutes),
                      textStyle,
                      digitStyle,
                    ),
                  ],
                ),
              );
            }
            return const Padding(
              padding: AppBookDetailTokens.statisticsItemPadding,
              child: AppLoadingIndicator(),
            );
          },
        );
      }

      final verticalDivider = VerticalDivider(
        color: Theme.of(context).colorScheme.outlineVariant,
        thickness: AppBookDetailTokens.statisticsDividerThickness,
        indent: AppBookDetailTokens.statisticsDividerIndent,
        endIndent: AppBookDetailTokens.statisticsDividerIndent,
      );

      return SizedBox(
        height: AppBookDetailTokens.statisticsHeight,
        width: MediaQuery.of(context).size.width,
        child: AppCard(
          padding: AppSpacing.zero,
          child: ListView(
            padding: AppBookDetailTokens.statisticsPadding,
            scrollDirection: Axis.horizontal,
            children: [
              Row(
                children: [
                  buildNthBooksItem(),
                  verticalDivider,
                  buildRankItem(),
                  verticalDivider,
                  buildReadingTimeItem(),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildTagEditor() {
      return SizedBox(
        width: MediaQuery.of(context).size.width,
        child: AppCard(
          margin: AppBookDetailTokens.tagEditorMargin,
          padding: AppBookDetailTokens.tagEditorPadding,
          child: AppAsyncValue<BookTagState>(
            value: ref.watch(bookTagEditorProvider(widget.book.id)),
            onRetry: () async {
              ref.invalidate(bookTagEditorProvider(widget.book.id));
              await ref.read(bookTagEditorProvider(widget.book.id).future);
            },
            dataBuilder: (context, state) {
              final notifier =
                  ref.read(bookTagEditorProvider(widget.book.id).notifier);
              Future<void> showTagEditDialog(Tag tag) async {
                await TagChip.showEditDialog(
                  context: context,
                  initialName: tag.name,
                  initialColor: tag.color ?? hashColor(tag.name),
                  onRename: (newName) async {
                    await ref
                        .read(tagListProvider.notifier)
                        .updateTag(tag.id, newName: newName);
                    if (!mounted) return;
                    ref.read(bookListProvider.notifier).refresh();
                    ref.invalidate(bookTagEditorProvider(widget.book.id));
                  },
                  onColorChange: (color) async {
                    await ref
                        .read(tagListProvider.notifier)
                        .updateTag(tag.id, color: color);
                    if (!mounted) return;
                    ref.read(bookListProvider.notifier).refresh();
                    ref.invalidate(bookTagEditorProvider(widget.book.id));
                  },
                  onDelete: () async {
                    await ref.read(tagListProvider.notifier).deleteTag(tag.id);
                    if (!mounted) return;
                    await notifier.detach(tag);
                    if (!mounted) return;
                    ref.read(bookListProvider.notifier).refresh();
                    ref.invalidate(bookTagEditorProvider(widget.book.id));
                  },
                );
              }

              Future<void> toggle(Tag tag) async {
                final currentlySelected = state.isAttached(tag.id);
                if (currentlySelected) {
                  await notifier.detach(tag);
                } else {
                  await notifier.attachExisting(tag);
                }
                if (!mounted) return;
                ref.read(bookListProvider.notifier).refresh();
              }

              final attachedTags =
                  state.tags.where((t) => state.isAttached(t.id)).toList();

              if (!isEditing) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.of(context).tagsSectionTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: AppSpacing.tokens.s8),
                    attachedTags.isEmpty
                        ? Column(
                            children: [
                              HintBanner(
                                margin: AppSpacing.vertical8,
                                hintKey: HintKey.addTags,
                                child: Text(L10n.of(context).tagsEditHint),
                              ),
                              Text(L10n.of(context).tagsEmptyHint),
                            ],
                          )
                        : Column(
                            children: [
                              Wrap(
                                spacing: AppSpacing.tokens.s8,
                                runSpacing: AppSpacing.tokens.s8,
                                children: attachedTags
                                    .map(
                                      (tag) => TagChip(
                                        label: tag.name,
                                        color: tag.color,
                                        selected: true,
                                        dense: true,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.of(context).tagsSectionTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: AppSpacing.tokens.s8),
                  Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppBookDetailTokens.tagInputMaxWidth,
                          ),
                          child: AppTextField(
                            controller: _newTagController,
                            hintText: L10n.of(context).tagNewPlaceholder,
                            enabled: !_creatingTag,
                            isDense: true,
                            contentPadding: AppBookDetailTokens.tagInputPadding,
                            onChanged: (_) {
                              setState(() {
                                final text = _newTagController.text.trim();
                                _pendingTagColor =
                                    text.isEmpty ? null : hashColor(text);
                              });
                            },
                            onSubmitted: (_) => _createTag(),
                          ),
                        ),
                      ),
                      SizedBox(width: AppSpacing.tokens.s8),
                      Builder(
                        builder: (context) {
                          final currentText = _newTagController.text.trim();
                          final defaultColor = _pendingTagColor ??
                              (currentText.isEmpty
                                  ? hashColor('tag')
                                  : hashColor(currentText));
                          return AppIconButton(
                            tooltip: L10n.of(context).tagColorTooltip,
                            enabled: currentText.isNotEmpty && !_creatingTag,
                            onPressed: () async {
                              final picked = await showRgbColorPicker(
                                context: context,
                                initialColor: defaultColor,
                                allowAlpha: false,
                              );
                              if (mounted && picked != null) {
                                setState(() => _pendingTagColor = picked);
                              }
                            },
                            child: Icon(Icons.circle, color: defaultColor),
                          );
                        },
                      ),
                      SizedBox(width: AppSpacing.tokens.s4),
                      AppButton(
                        label: L10n.of(context).tagAddButton,
                        variant: AppButtonVariant.outlined,
                        isLoading: _creatingTag,
                        onPressed: _createTag,
                      ),
                    ],
                  ),
                  if (_tagCreateFailed) ...[
                    SizedBox(height: AppSpacing.tokens.s8),
                    AppInlineFeedback(onRetry: _createTag),
                  ],
                  SizedBox(height: AppSpacing.tokens.s8),
                  if (state.tags.isNotEmpty)
                    HintBanner(
                      margin: AppSpacing.vertical8,
                      hintKey: HintKey.editOrRemoveTags,
                      child: Text(L10n.of(context).tagsEditOrRemoveHint),
                    ),
                  Wrap(
                    spacing: AppSpacing.tokens.s8,
                    runSpacing: AppSpacing.tokens.s8,
                    children: state.tags
                        .map((tag) => TagChip(
                              label: tag.name,
                              color: tag.color,
                              selected: state.isAttached(tag.id),
                              onTap: () => toggle(tag),
                              onLongPress: () => showTagEditDialog(tag),
                              dense: false,
                            ))
                        .toList(),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget buildMoreDetail() {
      Widget buildReadingDetail() {
        return FutureBuilder<List<ReadingTime>>(
          future: widget.readingTimeLoader?.call(widget.book.id) ??
              readingTimeDao.selectReadingTimeByBookId(widget.book.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppErrorState(
                onRetry: () async {
                  if (mounted) setState(() {});
                },
              );
            }
            if (snapshot.hasData) {
              final readingTimes = snapshot.data!;
              if (readingTimes.isEmpty) return const AppEmptyState();
              return Column(
                children: readingTimes.map((readingTime) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          readingTime.dateOnly ?? readingTime.date ?? '',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        convertSeconds(readingTime.readingTime),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  );
                }).toList(),
              );
            }
            return const Center(child: AppLoadingIndicator());
          },
        );
      }

      final textStyle = Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.bold);
      return SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: AppCard(
            padding: AppBookDetailTokens.moreDetailPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${L10n.of(context).bookDetailFileFormat}$_bookFileFormat',
                  style: textStyle,
                ),
                Text(
                  '${L10n.of(context).bookDetailImportDate}${widget.book.createTime.toString().substring(0, 10)}',
                  style: textStyle,
                ),
                Text(
                  '${L10n.of(context).bookDetailLastReadDate}${widget.book.updateTime.toString().substring(0, 10)}',
                  style: textStyle,
                ),
                const Divider(),
                buildReadingDetail(),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            setState(() {
              _isCollapsed = notification.metrics.pixels > 0;
            });
          }
          return false;
        },
        child: Stack(
          children: [
            buildBackground(),
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 0,
                  pinned: true,
                  stretch: true,
                  backgroundColor: _isCollapsed
                      ? Theme.of(context)
                          .colorScheme
                          .surface
                          .withAlpha(AppBookDetailTokens.collapsedAppBarAlpha)
                      : AppColors.transparent,
                  title: AnimatedOpacity(
                    opacity: _isCollapsed ? 1.0 : 0.0,
                    duration: AppMotion.tokens.emphasis,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.book.title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  centerTitle: true,
                ),
                SliverToBoxAdapter(
                  child: AppSafeArea(
                    top: false,
                    child: Padding(
                      padding: AppBookDetailTokens.pagePadding,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >
                              AppBookDetailTokens.wideBreakpoint) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      buildBookBaseDetail(
                                        constraints.maxWidth / 2 -
                                            AppBookDetailTokens.wideSpacing,
                                      ),
                                      buildTagEditor(),
                                      buildEditButton(),
                                      SizedBox(
                                        height: AppBookDetailTokens
                                            .editButtonSpacing,
                                      ),
                                      buildBookStatistics(),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: AppBookDetailTokens.wideSpacing,
                                ),
                                Expanded(
                                  child: Padding(
                                    padding:
                                        AppBookDetailTokens.wideDetailPadding,
                                    child: buildMoreDetail(),
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              buildBookBaseDetail(constraints.maxWidth),
                              buildTagEditor(),
                              buildEditButton(),
                              SizedBox(
                                height: AppBookDetailTokens.editButtonSpacing,
                              ),
                              buildBookStatistics(),
                              SizedBox(
                                height: AppBookDetailTokens.sectionSpacing,
                              ),
                              buildMoreDetail(),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
