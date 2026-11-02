import 'package:anx_reader/constants/note_annotations.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/time_to_human.dart';
import 'package:flutter/material.dart';

class BookNoteTile extends StatelessWidget {
  const BookNoteTile({
    super.key,
    required this.note,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.backgroundColor,
    this.margin = AppBookNotesTokens.tileMargin,
  });

  final BookNote note;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Color? backgroundColor;
  final EdgeInsetsGeometry margin;

  Icon _buildIcon(Color color) {
    final match = notesType.where((option) => option.type == note.type);
    if (match.isNotEmpty) {
      return Icon(match.first.icon, color: color);
    }
    return Icon(Icons.bookmark, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconColor = AppBookNotesTokens.tileIconColor(note.color);
    final infoStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);

    return AppCard(
      color: backgroundColor,
      padding: AppBookNotesTokens.tilePadding,
      margin: margin,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppBookNotesTokens.tileIconPadding,
            child: _buildIcon(iconColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.content,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (note.readerNote != null && note.readerNote!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: AppSpacing.tokens.s4),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            VerticalDivider(
                              thickness:
                                  AppBookNotesTokens.tileDividerThickness,
                              color: colors.outlineVariant,
                            ),
                            Expanded(
                              child: Text(
                                note.readerNote!,
                                style: infoStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.tokens.s4),
                    ],
                  ),
                Divider(
                  indent: AppBookNotesTokens.tileDividerIndent,
                  height: AppBookNotesTokens.tileDividerHeight,
                  color: colors.outlineVariant,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        note.chapter,
                        style: infoStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      timeToHuman(note.createTime),
                      style: infoStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
