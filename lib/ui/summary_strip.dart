/// The one-line headline counts above the item list.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/inventory_summary.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/ui/theme.dart';

/// How each sort option reads in the menu.
String sortLabel(ItemSort sort) => switch (sort) {
  ItemSort.updatedDesc => 'Recently changed',
  ItemSort.nameAsc => 'Name (A-Z)',
  ItemSort.createdDesc => 'Newest first',
  ItemSort.quantityAsc => 'Fewest first',
  ItemSort.locationAsc => 'By location',
  ItemSort.lowStockFirst => 'Running low first',
  ItemSort.expiringFirst => 'Expiring first',
};

/// Totals for the whole inventory, above the (possibly filtered) list.
///
/// Deliberately unfiltered: it answers "how much is there, and how much do I
/// need to buy" for the house, which is the question the strip is for. It
/// hides itself entirely at zero rather than reading "0 items · 0 to buy"
/// over an empty-state illustration that already says so.
class SummaryStrip extends StatelessWidget {
  /// Creates the strip.
  const SummaryStrip({required this.repository, super.key});

  /// Source of the counts.
  final ItemRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<InventorySummary>(
      stream: repository.watchSummary(),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? InventorySummary.empty;
        if (summary.total == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${summary.total} ${summary.total == 1 ? 'item' : 'items'}'
              ' · ${summary.toBuy} to buy',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
