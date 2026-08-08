/// One row in the item list.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/freshness_badge.dart';
import 'package:home_inventory/ui/stock_badge.dart';
import 'package:home_inventory/ui/theme.dart';

/// A list row showing what the thing is, how much there is, and where it is.
class ItemTile extends StatelessWidget {
  /// Creates a row for [item].
  const ItemTile({
    required this.item,
    this.locationLabel,
    this.onTap,
    this.asOf,
    super.key,
  });

  /// The item to show.
  final Item item;

  /// Resolved place, e.g. `korytarz › szafka z lewej`.
  ///
  /// Passed in rather than read off [item] because resolving an arbitrarily
  /// deep path means walking location records, which a widget has no business
  /// doing. Null falls back to the legacy strings, which is what an item that
  /// has not been migrated yet still has.
  final String? locationLabel;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  /// Clock for the best-before badge; defaults to now.
  ///
  /// Injectable so a widget test can assert on a date badge without the
  /// answer changing between the day the test was written and the day it
  /// runs.
  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final freshness = item.freshnessAt(asOf ?? DateTime.now());
    final quantity = item.unit.isEmpty
        ? formatQuantity(item.quantity)
        : '${formatQuantity(item.quantity)} ${item.unit}';
    final place = locationLabel ?? item.legacyLocation;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (freshness != null) ...[
            FreshnessBadge(freshness: freshness),
            const SizedBox(width: AppSpacing.xs),
          ],
          StockBadge(state: item.stockState),
        ],
      ),
      subtitle: Text(
        // The location is the answer to "where is it", so it earns the
        // subtitle even when empty-ish; the quantity leads because it is what
        // changes.
        place.isEmpty ? quantity : '$quantity  ·  $place',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
