/// The best-before indicator shown next to a dated item.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/ui/theme.dart';

/// A small pill naming how close an item is to its date, or nothing at all
/// while it is still [FreshnessState.fresh].
///
/// Silent-when-fine, exactly like `StockBadge`: a date pill on every row
/// would drown the two rows that actually need buying or eating today.
class FreshnessBadge extends StatelessWidget {
  /// Creates a badge for [freshness].
  const FreshnessBadge({required this.freshness, super.key});

  /// The reading to render.
  final Freshness freshness;

  @override
  Widget build(BuildContext context) {
    if (freshness.state == FreshnessState.fresh) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final status = theme.extension<AppStatusColors>()!;
    // Two-way, not an exhaustive switch: `fresh` already returned above, so a
    // third arm would be dead code the coverage gate could never satisfy.
    final isExpired = freshness.state == FreshnessState.expired;
    final color = isExpired ? theme.colorScheme.error : status.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        freshness.label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
