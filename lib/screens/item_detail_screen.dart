/// One item in full: how much, where, and how fast it is going.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/screens/item_form_screen.dart';
import 'package:home_inventory/ui/quantity_stepper.dart';
import 'package:home_inventory/ui/stock_badge.dart';
import 'package:home_inventory/ui/theme.dart';

/// Detail view for a single item.
class ItemDetailScreen extends StatelessWidget {
  /// Creates the detail screen for [itemId].
  const ItemDetailScreen({
    required this.repository,
    required this.itemId,
    this.now,
    super.key,
  });

  /// Store to read and write.
  final ItemRepository repository;

  /// Which item to show.
  final String itemId;

  /// Injectable clock, so tests get deterministic timestamps.
  final DateTime Function()? now;

  DateTime _clock() => (now ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Item?>(
      stream: repository.watchItem(itemId),
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) {
          // Covers both "still loading" and "deleted from another screen";
          // either way there is nothing to show and no error to report.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _DetailBody(
          repository: repository,
          item: item,
          clock: _clock,
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.repository,
    required this.item,
    required this.clock,
  });

  final ItemRepository repository;
  final Item item;
  final DateTime Function() clock;

  Future<void> _edit(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<Item>(
        builder: (_) => ItemFormScreen(repository: repository, item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = repository.rateHint(item.id, now: clock());
    final history = repository.historyFor(item.id).reversed.toList();
    // Resolved here rather than on the model: walking an arbitrarily deep
    // parent chain needs the other records. Falls back to the legacy strings
    // for an item that has not been migrated yet.
    final place = item.locationId.isEmpty
        ? item.legacyLocation
        : repository.pathLabel(item.locationId);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          QuantityStepper(
            quantity: item.quantity,
            unit: item.unit,
            onUse: () => repository.adjustQuantity(
              item.id,
              -1,
              AdjustmentSource.use,
              now: clock(),
            ),
            onRestock: () => repository.adjustQuantity(
              item.id,
              1,
              AdjustmentSource.restock,
              now: clock(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(child: StockBadge(state: item.stockState)),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Text(
                hint.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Divider(),
          if (place.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(place),
            ),
          if (item.category.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(item.category),
            ),
          if (item.notes.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(item.notes),
            ),
          if (history.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('History', style: theme.textTheme.titleMedium),
            ),
            for (final entry in history)
              ListTile(
                dense: true,
                title: Text(_describe(entry)),
                subtitle: Text(
                  '${entry.at.year}-${_two(entry.at.month)}-'
                  '${_two(entry.at.day)}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _describe(Adjustment entry) {
    final amount = formatQuantity(entry.delta.abs());
    return switch (entry.source) {
      AdjustmentSource.use => 'Used $amount',
      AdjustmentSource.restock => 'Added $amount',
      AdjustmentSource.correction =>
        'Recounted to ${entry.delta > 0 ? '+' : '−'}$amount',
      AdjustmentSource.initial => 'Added $amount to start',
    };
  }
}
