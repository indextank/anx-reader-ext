import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';

class ReadingNotes extends StatelessWidget {
  const ReadingNotes({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (screenHeight * 0.7).clamp(0.0, screenHeight);
        return Container(
          padding: AppReadingTokens.panelPadding,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widgetTitle(L10n.of(context).navBarNotes, null),
              Expanded(
                child: ListView(
                  children: [BookNotesList(book: book, reading: true)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
