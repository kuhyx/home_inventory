/// The placeholder shown when a list has nothing in it.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// A centred icon, headline and explanation for an empty list.
class EmptyState extends StatelessWidget {
  /// Creates an empty-state placeholder.
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  /// Glyph shown above the text.
  final IconData icon;

  /// Short headline, e.g. "Nothing here yet".
  final String title;

  /// One line explaining what to do about it.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
