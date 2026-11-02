import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BookshelfTips extends StatelessWidget {
  const BookshelfTips({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.all24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '(´。＿。｀)',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: AppSpacing.tokens.s48),
            Text(
              L10n.of(context).bookshelfTips_1,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.tokens.s8),
            Text(
              L10n.of(context).bookshelfTips_2,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
