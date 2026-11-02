import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/notes/notes_json.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Pick a notes JSON file and import into [book], with match / risk prompts.
Future<int?> importNotesJsonForBook(BuildContext context, Book book) async {
  final l10n = L10n.of(context);

  final confirmedRisk = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.notesJsonImportTitle),
      content: Text(l10n.notesJsonImportRisk),
      actions: [
        AppButton(
          label: l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        AppButton(
          label: l10n.commonConfirm,
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (confirmedRisk != true) return null;
  if (!context.mounted) return null;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.single;
  String raw;
  if (file.bytes != null) {
    raw = utf8.decode(file.bytes!);
  } else if (file.path != null) {
    raw = await File(file.path!).readAsString();
  } else {
    AnxToast.show(l10n.notesJsonImportFailed);
    return null;
  }

  final NotesJsonPayload payload;
  try {
    payload = NotesJsonPayload.decode(raw);
  } catch (e) {
    AnxToast.show(l10n.notesJsonImportInvalid);
    return null;
  }

  final match = matchNotesJsonToBook(payload.book, book);
  if (match == NotesJsonMatchKind.none) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.notesJsonImportTitle),
          content: Text(l10n.notesJsonImportNoMatch),
          actions: [
            AppButton(
              label: l10n.commonOk,
              variant: AppButtonVariant.primary,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    }
    return null;
  }

  if (match == NotesJsonMatchKind.fuzzyTitleAuthor) {
    if (!context.mounted) return null;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.commonAttention),
        content: Text(l10n.notesJsonImportFuzzyWarn),
        actions: [
          AppButton(
            label: l10n.commonCancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: l10n.commonConfirm,
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (proceed != true) return null;
  }

  final imported = await applyNotesJsonImport(book, payload.notes);
  AnxToast.show(l10n.notesJsonImportSuccess(imported));
  return imported;
}

/// Import notes into [book], deduping via [BookNoteDao.save] (cfi + bookId).
Future<int> applyNotesJsonImport(Book book, List<BookNote> notes) async {
  var count = 0;
  for (final note in notes) {
    final toSave = BookNote(
      bookId: book.id,
      content: note.content,
      cfi: note.cfi,
      chapter: note.chapter,
      type: note.type,
      color: note.color,
      readerNote: note.readerNote,
      createTime: note.createTime ?? DateTime.now(),
      updateTime: note.updateTime,
    );
    await bookNoteDao.save(toSave);
    count++;
  }
  return count;
}
