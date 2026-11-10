/// The best-before indicator shown next to a dated item.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/ui/status_pill.dart';
import 'package:home_inventory/ui/theme.dart';

/// Glyph for each [FreshnessState], shared by the badges and the filter chips.
IconData freshnessGlyph(FreshnessState state) => switch (state) {
  FreshnessState.fresh => Icons.eco_outlined,
  FreshnessState.dueSoon => Icons.schedule,
  FreshnessState.expired => Icons.event_busy,
};

/// Spoken-only name of each [FreshnessState].
String freshnessSpoken(FreshnessState state) => switch (state) {
  FreshnessState.fresh => 'Fresh',
  FreshnessState.dueSoon => 'Due soon',
  FreshnessState.expired => 'Expired',
};

/// A small pill showing how close an item is to its date, or nothing at all
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
    return StatusPill(
      icon: freshnessGlyph(freshness.state),
      color: isExpired ? theme.colorScheme.error : status.warning,
      semanticLabel: freshness.label,
      // Days left as a bare number: the clock glyph already says "days".
      value: isExpired ? null : '${freshness.daysLeft}',
    );
  }
}
