import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:anx_reader/widgets/context_menu/reader_note_menu.dart';
import 'package:anx_reader/widgets/context_menu/search_menu.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';

Rect readingMenuSafeViewport(Rect viewport, EdgeInsets padding) {
  return padding.deflateRect(viewport);
}

class ReadingMenuGeometry {
  const ReadingMenuGeometry({
    required this.selectionRect,
    required this.safeViewportRect,
    required this.bottomInset,
    required this.menuConstraints,
  });

  factory ReadingMenuGeometry.resolve({
    required Rect viewportRect,
    required EdgeInsets padding,
    required EdgeInsets viewInsets,
    required Rect normalizedSelection,
    required bool footnote,
  }) {
    const horizontalMargin = 16.0;
    const verticalMargin = 16.0;
    final safeViewportRect = readingMenuSafeViewport(viewportRect, padding);
    final selectionRect = Rect.fromLTRB(
      viewportRect.left + normalizedSelection.left * viewportRect.width,
      viewportRect.top + normalizedSelection.top * viewportRect.height,
      viewportRect.left + normalizedSelection.right * viewportRect.width,
      viewportRect.top + normalizedSelection.bottom * viewportRect.height,
    );
    final maxWidth = math.min(
      350.0,
      math.max(120.0, safeViewportRect.width - horizontalMargin * 2),
    );
    final effectiveHeight = math.max(
      0.0,
      safeViewportRect.height - viewInsets.bottom,
    );
    final maxHeightCandidate = effectiveHeight - verticalMargin * 2;
    final rawMaxHeight = math.min(
      footnote ? 350.0 : 550.0,
      math.max(200.0, maxHeightCandidate),
    );
    final maxHeight = math.max(
      0.0,
      math.min(rawMaxHeight, maxHeightCandidate),
    );

    return ReadingMenuGeometry(
      selectionRect: selectionRect,
      safeViewportRect: safeViewportRect,
      bottomInset: viewInsets.bottom,
      menuConstraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
    );
  }

  final Rect selectionRect;
  final Rect safeViewportRect;
  final double bottomInset;
  final BoxConstraints menuConstraints;
}

Future<void> showContextMenu(
    BuildContext context,
    double left,
    double top,
    double right,
    double bottom,
    String annoContent,
    String annoCfi,
    int? annoId,
    bool footnote,
    Axis axis,
    {String? contextText}) async {
  final playerKey = epubPlayerKey.currentState;
  if (playerKey == null) return;
  bool isNewNote = false;

  if (Prefs().autoMarkSelection && annoId == null) {
    // Auto-highlight logic
    final String type = Prefs().annotationType;
    final String color = Prefs().annotationColor;

    final BookNote bookNote = BookNote(
      bookId: playerKey.book.id,
      content: annoContent,
      cfi: annoCfi,
      chapter: playerKey.chapterTitle,
      type: type,
      color: color,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );

    final id = await bookNoteDao.save(bookNote);
    bookNote.setId(id);
    playerKey.addAnnotation(bookNote);
    annoId = id;
    isNewNote = true;
  }

  if (!context.mounted) return;

  const double horizontalMargin = 16;
  const double verticalMargin = 16;
  const double gap = 12;
  final normalizedSelection = Rect.fromLTRB(left, top, right, bottom);

  ReadingMenuGeometry resolveGeometry(BuildContext menuContext) {
    final renderBox =
        epubPlayerKey.currentContext?.findRenderObject() as RenderBox?;
    final mediaQuery = MediaQuery.of(menuContext);
    final size = renderBox?.size ?? mediaQuery.size;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    return ReadingMenuGeometry.resolve(
      viewportRect:
          Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
      padding: mediaQuery.padding,
      viewInsets: mediaQuery.viewInsets,
      normalizedSelection: normalizedSelection,
      footnote: footnote,
    );
  }

  final initialGeometry = resolveGeometry(context);
  final initialPlacement = resolveReadingMenuPlacement(
    axis: axis,
    geometry: initialGeometry,
    menuSize: Size(
      initialGeometry.menuConstraints.maxWidth,
      initialGeometry.menuConstraints.maxHeight,
    ),
    horizontalMargin: horizontalMargin,
    verticalMargin: verticalMargin,
    gap: gap,
  );

  playerKey.removeOverlay();

  void onClose() {
    playerKey.webViewController.execute('clearSelection()');
    playerKey.removeOverlay();
    playerKey.restoreReaderFocus();
  }

  final decoration = BoxDecoration(
    color: Prefs().eInkMode
        ? AppColors.white
        : Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: AppReadingTokens.contextMenuRadius,
    boxShadow: [
      if (!Prefs().eInkMode)
        BoxShadow(
          color: AppColors.black.withValues(alpha: 0.1),
          spreadRadius: 5,
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      if (Prefs().eInkMode)
        const BoxShadow(
          color: AppColors.black,
          spreadRadius: 1,
          blurRadius: 0,
        ),
    ],
  );

  playerKey.contextMenuEntry = OverlayEntry(builder: (context) {
    return ReadingContextMenuOverlay(
      axis: axis,
      initialGeometry: initialGeometry,
      geometryResolver: resolveGeometry,
      annoContent: annoContent,
      annoCfi: annoCfi,
      annoId: annoId,
      footnote: footnote,
      contextText: contextText,
      decoration: decoration,
      onClose: onClose,
      initialPlacement: initialPlacement,
      showTranslationDefault: !isNewNote && Prefs().autoTranslateSelection,
      horizontalMargin: horizontalMargin,
      verticalMargin: verticalMargin,
      gap: gap,
    );
  });

  Overlay.of(context).insert(playerKey.contextMenuEntry!);
}

class ReadingMenuPlacement {
  const ReadingMenuPlacement({
    required this.offset,
    required this.shouldReverse,
  });

  final Offset offset;
  final bool shouldReverse;
}

double _clampWithin(double value, double min, double max) {
  if (min > max) {
    return min;
  }
  return value.clamp(min, max);
}

ReadingMenuPlacement resolveReadingMenuPlacement({
  required Axis axis,
  required ReadingMenuGeometry geometry,
  required Size menuSize,
  required double horizontalMargin,
  required double verticalMargin,
  required double gap,
}) {
  final menuWidth = menuSize.width;
  final menuHeight = menuSize.height;
  final selectionRect = geometry.selectionRect;
  final viewportRect = geometry.safeViewportRect;
  final clampedViewportBottom = math.max(
    viewportRect.top,
    viewportRect.bottom - geometry.bottomInset,
  );

  if (axis == Axis.horizontal) {
    final spaceAbove = selectionRect.top - viewportRect.top;
    final spaceBelow = clampedViewportBottom - selectionRect.bottom;
    final placeBelow =
        (spaceBelow >= menuHeight + gap) || (spaceBelow >= spaceAbove);

    final minTop = viewportRect.top + verticalMargin;
    final maxTop = clampedViewportBottom - menuHeight - verticalMargin;
    double desiredTop = placeBelow
        ? selectionRect.bottom + gap
        : selectionRect.top - menuHeight - gap;
    desiredTop = _clampWithin(desiredTop, minTop, maxTop);

    final minLeft = viewportRect.left + horizontalMargin;
    final maxLeft = viewportRect.right - menuWidth - horizontalMargin;
    double desiredLeft = selectionRect.center.dx - menuWidth / 2;
    desiredLeft = _clampWithin(desiredLeft, minLeft, maxLeft);

    return ReadingMenuPlacement(
      offset: Offset(desiredLeft, desiredTop),
      shouldReverse: !placeBelow,
    );
  }

  final spaceLeft = selectionRect.left - viewportRect.left;
  final spaceRight = viewportRect.right - selectionRect.right;
  final placeRight =
      (spaceRight >= menuWidth + gap) || (spaceRight >= spaceLeft);

  final minLeft = viewportRect.left + horizontalMargin;
  final maxLeft = viewportRect.right - menuWidth - horizontalMargin;
  double desiredLeft = placeRight
      ? selectionRect.right + gap
      : selectionRect.left - menuWidth - gap;
  desiredLeft = _clampWithin(desiredLeft, minLeft, maxLeft);

  final minTop = viewportRect.top + verticalMargin;
  final maxTop = clampedViewportBottom - menuHeight - verticalMargin;
  double desiredTop = selectionRect.center.dy - menuHeight / 2;
  desiredTop = _clampWithin(desiredTop, minTop, maxTop);

  return ReadingMenuPlacement(
    offset: Offset(desiredLeft, desiredTop),
    shouldReverse: !placeRight,
  );
}

class ReadingContextMenuOverlay extends StatefulWidget {
  const ReadingContextMenuOverlay({
    super.key,
    required this.axis,
    required this.initialGeometry,
    required this.geometryResolver,
    required this.annoContent,
    required this.annoCfi,
    required this.annoId,
    required this.footnote,
    this.contextText,
    required this.decoration,
    required this.onClose,
    required this.initialPlacement,
    required this.showTranslationDefault,
    required this.horizontalMargin,
    required this.verticalMargin,
    required this.gap,
    this.menuBuilder,
  });

  final Axis axis;
  final ReadingMenuGeometry initialGeometry;
  final ReadingMenuGeometry Function(BuildContext context) geometryResolver;
  final String annoContent;
  final String annoCfi;
  final int? annoId;
  final bool footnote;
  final String? contextText;
  final BoxDecoration decoration;
  final VoidCallback onClose;
  final ReadingMenuPlacement initialPlacement;
  final bool showTranslationDefault;
  final double horizontalMargin;
  final double verticalMargin;
  final double gap;
  final WidgetBuilder? menuBuilder;

  @override
  State<ReadingContextMenuOverlay> createState() =>
      ReadingContextMenuOverlayState();
}

class ReadingContextMenuOverlayState extends State<ReadingContextMenuOverlay>
    with WidgetsBindingObserver {
  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey<ReaderNoteMenuState> _readerNoteMenuKey =
      GlobalKey<ReaderNoteMenuState>();

  late Offset _position;
  late bool _reverse;
  late bool _showTranslationMenu;
  bool _showReaderNoteMenu = false;
  bool _showSearchMenu = false;
  String _searchQuery = '';
  bool _waitingForFirstMeasurement = true;
  late BoxConstraints _menuConstraints;
  late double _bottomInset;
  int? _noteId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _position = widget.initialPlacement.offset;
    _reverse = widget.initialPlacement.shouldReverse;
    _showTranslationMenu = widget.showTranslationDefault;
    _noteId = widget.annoId;
    _bottomInset = widget.initialGeometry.bottomInset;
    _menuConstraints = widget.initialGeometry.menuConstraints;
    _scheduleRecalculate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    epubPlayerKey.currentState?.setSelectionClearLocked(false);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleRecalculate();
  }

  void _scheduleRecalculate({Duration delay = Duration.zero}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (delay == Duration.zero) {
        _updatePlacement();
      } else {
        Future.delayed(delay, () {
          if (!mounted) return;
          _updatePlacement();
        });
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    _scheduleRecalculate();
  }

  void _updatePlacement() {
    final renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    final geometry = widget.geometryResolver(context);
    final newConstraints = geometry.menuConstraints;

    if (renderBox == null) {
      final needsStateUpdate =
          (_bottomInset - geometry.bottomInset).abs() > 0.5 ||
              _menuConstraints.maxHeight != newConstraints.maxHeight;

      if (needsStateUpdate) {
        setState(() {
          _bottomInset = geometry.bottomInset;
          _menuConstraints = newConstraints;
        });
      }
      return;
    }

    final placement = resolveReadingMenuPlacement(
      axis: widget.axis,
      geometry: geometry,
      menuSize: renderBox.size,
      horizontalMargin: widget.horizontalMargin,
      verticalMargin: widget.verticalMargin,
      gap: widget.gap,
    );

    final positionChanged = (_position.dx - placement.offset.dx).abs() > 0.5 ||
        (_position.dy - placement.offset.dy).abs() > 0.5;
    final bottomInsetChanged =
        (_bottomInset - geometry.bottomInset).abs() > 0.5;
    final constraintsChanged =
        _menuConstraints.maxHeight != newConstraints.maxHeight;

    final shouldUpdate = _waitingForFirstMeasurement ||
        positionChanged ||
        _reverse != placement.shouldReverse ||
        bottomInsetChanged ||
        constraintsChanged;

    if (shouldUpdate) {
      setState(() {
        _position = placement.offset;
        _reverse = placement.shouldReverse;
        _bottomInset = geometry.bottomInset;
        _menuConstraints = newConstraints;
        _waitingForFirstMeasurement = false;
      });
    }
  }

  void _toggleTranslationMenu() {
    setState(() {
      _showTranslationMenu = !_showTranslationMenu;
    });
    _scheduleRecalculate();
  }

  void _toggleReaderNoteMenu({bool? show}) {
    final target = show ?? !_showReaderNoteMenu;
    epubPlayerKey.currentState?.setSelectionClearLocked(target);
    setState(() {
      _showReaderNoteMenu = target;
    });
    _scheduleRecalculate(
      delay: _showReaderNoteMenu
          ? const Duration(milliseconds: 300)
          : Duration.zero,
    );
  }

  void _toggleSearchMenu({bool? show, String? query}) {
    final target = show ?? !_showSearchMenu;
    epubPlayerKey.currentState?.setSelectionClearLocked(target);
    setState(() {
      _showSearchMenu = target;
      if (query != null) _searchQuery = query;
    });
    _scheduleRecalculate(
      delay:
          _showSearchMenu ? const Duration(milliseconds: 300) : Duration.zero,
    );
  }

  Future<void> _openReaderNoteMenu(int noteId) async {
    _toggleReaderNoteMenu(show: true);
    if (_readerNoteMenuKey.currentState == null) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await _readerNoteMenuKey.currentState?.showNoteDialog(noteId);
    _scheduleRecalculate(delay: const Duration(milliseconds: 300));
  }

  void _handleNoteCreated(int noteId) {
    if (_noteId == noteId) {
      return;
    }
    setState(() {
      _noteId = noteId;
    });
  }

  void _handleReaderNoteVisibilityChange(bool visible) {
    epubPlayerKey.currentState?.setSelectionClearLocked(visible);
    if (_showReaderNoteMenu == visible) {
      return;
    }
    setState(() {
      _showReaderNoteMenu = visible;
    });
    _scheduleRecalculate(
      delay: visible ? const Duration(milliseconds: 300) : Duration.zero,
    );
  }

  void _handleReaderNoteSizeChanged() {
    _scheduleRecalculate();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: PointerInterceptor(
        child: Stack(
          children: [
            GestureDetector(
              onTap: widget.onClose,
              child: IgnorePointer(
                ignoring: _waitingForFirstMeasurement,
                child: Opacity(
                  opacity: _waitingForFirstMeasurement ? 0 : 1,
                  child: Container(
                    key: _menuKey,
                    color: AppColors.transparent,
                    constraints: _menuConstraints,
                    child: widget.menuBuilder?.call(context) ??
                        AxisFlex(
                          axis: flipAxis(widget.axis),
                          reverse: _reverse,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AxisFlex(
                              axis: flipAxis(widget.axis),
                              reverse: _reverse,
                              children: [
                                AxisFlex(
                                  axis: widget.axis,
                                  children: [
                                    ExcerptMenu(
                                      annoCfi: widget.annoCfi,
                                      annoContent: widget.annoContent,
                                      id: widget.annoId,
                                      onClose: widget.onClose,
                                      footnote: widget.footnote,
                                      decoration: widget.decoration,
                                      toggleTranslationMenu:
                                          _toggleTranslationMenu,
                                      toggleReaderNoteMenu:
                                          _toggleReaderNoteMenu,
                                      toggleSearchMenu: _toggleSearchMenu,
                                      openReaderNoteMenu: _openReaderNoteMenu,
                                      onNoteCreated: _handleNoteCreated,
                                      axis: widget.axis,
                                      reverse: _reverse,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (_showReaderNoteMenu) ...[
                              const SizedBox.square(dimension: 10),
                              AxisFlex(
                                axis: widget.axis,
                                children: [
                                  ReaderNoteMenu(
                                    key: _readerNoteMenuKey,
                                    noteId: _noteId,
                                    decoration: widget.decoration,
                                    axis: widget.axis,
                                    onVisibilityChange:
                                        _handleReaderNoteVisibilityChange,
                                    onSizeChanged: _handleReaderNoteSizeChanged,
                                    onSaved: widget.onClose,
                                  ),
                                ],
                              ),
                            ],
                            if (_showTranslationMenu) ...[
                              const SizedBox.square(dimension: 10),
                              AxisFlex(
                                axis: widget.axis,
                                children: [
                                  TranslationMenu(
                                    content: widget.annoContent,
                                    decoration: widget.decoration,
                                    axis: widget.axis,
                                    contextText: widget.contextText,
                                  ),
                                ],
                              ),
                            ],
                            if (_showSearchMenu) ...[
                              const SizedBox.square(dimension: 10),
                              AxisFlex(
                                axis: widget.axis,
                                children: [
                                  SearchMenu(
                                    query: _searchQuery,
                                    decoration: widget.decoration,
                                    axis: widget.axis,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
