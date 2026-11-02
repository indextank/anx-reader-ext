import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

class ReaderNoteMenu extends StatefulWidget {
  const ReaderNoteMenu({
    super.key,
    this.noteId,
    required this.decoration,
    required this.axis,
    required this.onVisibilityChange,
    required this.onSizeChanged,
    this.onSaved,
    this.noteLoader,
    this.noteSaver,
  });

  final int? noteId;
  final BoxDecoration decoration;
  final Axis axis;
  final ValueChanged<bool> onVisibilityChange;
  final VoidCallback onSizeChanged;
  final VoidCallback? onSaved;
  final Future<BookNote?> Function(int id)? noteLoader;
  final Future<void> Function(BookNote? note, String text)? noteSaver;

  @override
  State<ReaderNoteMenu> createState() => ReaderNoteMenuState();
}

class ReaderNoteMenuState extends State<ReaderNoteMenu> {
  BookNote? note;
  bool _showNoteDialog = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _savePending = false;
  bool _saveFailed = false;
  final textFieldController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode(debugLabel: 'reader_note');
  bool showSaveButton = false;

  @override
  void initState() {
    super.initState();
    getNoteDetail(widget.noteId);
  }

  @override
  void dispose() {
    textFieldController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _focusNoteField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      readingPageKey.currentState?.releaseReaderFocusForChrome();
      _noteFocusNode.requestFocus();
    });
  }

  void _notifyVisibility(bool visible) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisibilityChange(visible);
    });
  }

  void _notifySizeChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSizeChanged();
    });
  }

  void _setShowNoteDialog(bool value) {
    if (!mounted) {
      _showNoteDialog = value;
      return;
    }
    setState(() => _showNoteDialog = value);
    _notifyVisibility(value);
    _notifySizeChange();
    if (value) _focusNoteField();
  }

  Future<void> getNoteDetail(int? id) async {
    if (id == null || _loading) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final loader = widget.noteLoader;
      final fetchedNote = loader != null
          ? await loader(id)
          : await bookNoteDao.selectBookNoteById(id);
      if (!mounted) return;
      note = fetchedNote;
      final readerNote = fetchedNote?.readerNote;
      if (readerNote != null && readerNote.isNotEmpty) {
        textFieldController.text = readerNote;
        _setShowNoteDialog(true);
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _notifySizeChange();
      }
    }
  }

  Future<void> showNoteDialog(int noteId) async {
    await getNoteDetail(noteId);
    if (!mounted) return;
    _setShowNoteDialog(true);
  }

  Future<void> saveNote() async {
    if (_savePending) return;
    final text = textFieldController.text.trim();
    setState(() {
      _savePending = true;
      _saveFailed = false;
    });
    try {
      final saver = widget.noteSaver;
      if (saver != null) {
        await saver(note, text);
      } else if (note != null) {
        note!.readerNote = text;
        await bookNoteDao.updateBookNoteById(note!);
      }
      if (!mounted) return;
      textFieldController.text = text;
      if (mounted) setState(() => showSaveButton = false);
      _notifySizeChange();
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _savePending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    Widget content;
    if (_loading) {
      content = const Center(child: AppLoadingIndicator());
    } else if (_loadFailed) {
      content = AppErrorState(
        compact: true,
        onRetry: () => getNoteDetail(widget.noteId),
      );
    } else if (!_showNoteDialog) {
      content = const SizedBox.shrink();
    } else {
      content = Container(
        decoration: widget.decoration,
        padding: AppReadingTokens.menuPadding,
        child: AxisFlex(
          axis: widget.axis,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: AppTextField(
                  controller: textFieldController,
                  focusNode: _noteFocusNode,
                  autofocus: true,
                  enabled: !_savePending,
                  border: InputBorder.none,
                  hintText: l10n.contextMenuAddNoteTips,
                  maxLines: widget.axis == Axis.vertical
                      ? double.maxFinite.toInt()
                      : 5,
                  minLines: 1,
                  onSubmitted: (_) => saveNote(),
                  onChanged: (_) {
                    setState(() => showSaveButton = true);
                    _notifySizeChange();
                  },
                ),
              ),
            ),
            if (showSaveButton || _savePending)
              AppIconButton(
                icon: EvaIcons.checkmark_circle_2_outline,
                tooltip: l10n.commonSave,
                isLoading: _savePending,
                onPressed: saveNote,
              ),
          ],
        ),
      );
    }

    return Expanded(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.axis == Axis.vertical
                ? double.infinity
                : AppReadingTokens.noteMenuMaxHeight,
            maxWidth: widget.axis == Axis.vertical
                ? AppReadingTokens.noteMenuVerticalWidth
                : double.infinity,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: content),
              if (_saveFailed)
                AppInlineFeedback(
                  message: l10n.commonActionFailed,
                  onRetry: saveNote,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
