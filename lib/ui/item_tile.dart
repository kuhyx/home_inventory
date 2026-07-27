/// One row in the item list.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/stock_badge.dart';
import 'package:home_inventory/ui/theme.dart';

/// A list row showing what the thing is, how much there is, and where it is.
class ItemTile extends StatelessWidget {
  /// Creates a row for [item].
  const ItemTile({required this.item, this.onTap, super.key});

  /// The item to show.
  final Item item;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = item.unit.isEmpty
        ? formatQuantity(item.quantity)
        : '${formatQuantity(item.quantity)} ${item.unit}';
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          StockBadge(state: item.stockState),
        ],
      ),
      subtitle: Text(
        // The location is the answer to "where is it", so it earns the
        // subtitle even when empty-ish; the quantity leads because it is what
        // changes.
        item.location.isEmpty ? quantity : '$quantity  ·  ${item.location}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
