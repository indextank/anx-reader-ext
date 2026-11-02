import 'dart:io';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:flutter/material.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.radius,
  });

  final Book book;
  final double? height;
  final double? width;
  final double? radius;

  Color _getContrastColor(Color backgroundColor) {
    final brightness = ThemeData.estimateBrightnessForColor(backgroundColor);
    return brightness == Brightness.dark ? AppColors.white : AppColors.black;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = radius ?? AppBookshelfTokens.coverRadius;
    final borderRadius = AppBookshelfTokens.coverBorderRadius(effectiveRadius);
    final file = File(book.coverFullPath);

    Widget child;

    if (file.existsSync()) {
      child = Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      child = LayoutBuilder(
        builder: (context, constraints) {
          final coverWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : Prefs().bookCoverWidth;
          final titleFontSize =
              coverWidth * AppBookshelfTokens.coverTitleFactor;
          final authorFontSize =
              coverWidth * AppBookshelfTokens.coverAuthorFactor;
          final iconSize = coverWidth * AppBookshelfTokens.coverIconFactor;
          final padding = coverWidth * AppBookshelfTokens.coverPaddingFactor;
          final palette = AppColors.bookCoverPalette;
          final backgroundColor =
              palette[book.title.hashCode.abs() % palette.length];
          final textColor = _getContrastColor(backgroundColor);
          final showTitle = Prefs().showBookTitleOnDefaultCover;
          final showAuthor = Prefs().showAuthorOnDefaultCover;

          return Container(
            color: backgroundColor,
            child: Stack(
              children: [
                if (showTitle || showAuthor)
                  Padding(
                    padding: AppBookshelfTokens.coverPadding(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showTitle)
                          Text(
                            book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                          ),
                        const Spacer(),
                        if (showAuthor)
                          Text(
                            book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: authorFontSize,
                                      fontWeight: FontWeight.w300,
                                      color: textColor,
                                    ),
                          ),
                      ],
                    ),
                  ),
                Positioned(
                  right: -padding * 0.8,
                  bottom: -padding * 0.5,
                  child: Transform.rotate(
                    angle: AppBookshelfTokens.coverIconRotation * math.pi / 180,
                    child: Icon(
                      Icons.book,
                      size: iconSize,
                      color: textColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final borderShape = RoundedSuperellipseBorder(
      borderRadius: borderRadius,
      side: BorderSide(
        width: AppBookshelfTokens.coverBorderWidth,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );

    return SizedBox(
      height: height,
      width: width,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(shape: borderShape),
        child: ClipRSuperellipse(
          borderRadius: borderRadius,
          child: child,
        ),
      ),
    );
  }
}
