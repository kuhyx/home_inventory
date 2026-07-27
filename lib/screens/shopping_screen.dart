/// "What do I need, and what can I sell?"
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/item_tile.dart';

/// The two outward-facing lists: things to buy, and things to get rid of.
class ShoppingScreen extends StatelessWidget {
  /// Creates the shopping screen.
  const ShoppingScreen({required this.repository, this.now, super.key});

  /// Store to read and restock through.
  final ItemRepository repository;

  /// Injectable clock, so a restock's timestamp is controllable in tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Shopping'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'To buy'),
            Tab(text: 'To sell'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _ItemList(
            stream: repository.watchToBuy(),
            repository: repository,
            now: now,
            emptyIcon: Icons.shopping_cart_outlined,
            emptyTitle: 'Nothing to buy',
            emptyMessage:
                'Everything is above its threshold, and nothing is marked '
                'as wanted.',
            showRestock: true,
          ),
          _ItemList(
            stream: repository.watchSellable(),
            repository: repository,
            now: now,
            emptyIcon: Icons.sell_outlined,
            emptyTitle: 'Nothing to sell',
            emptyMessage: 'Mark an item as sellable and it will show up here.',
            showRestock: false,
          ),
        ],
      ),
    ),
  );
}

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.stream,
    required this.repository,
    required this.now,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.showRestock,
  });

  final Stream<List<Item>> stream;
  final ItemRepository repository;
  final DateTime Function()? now;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final bool showRestock;

  Future<void> _open(BuildContext context, Item item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailScreen(
          repository: repository,
          itemId: item.id,
          now: now,
        ),
      ),
    );
  }

  /// Records buying one more of [item], without leaving the list.
  ///
  /// One unit per tap rather than "top up to the threshold": the threshold is
  /// what counts as *enough*, not what was in the bag, and a wrong guess here
  /// writes a permanent adjustment record. Tapping twice is cheap; the detail
  /// screen takes an exact number.
  Future<void> _bought(BuildContext context, Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    await repository.adjustQuantity(
      item.id,
      1,
      AdjustmentSource.restock,
      now: now?.call(),
    );
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Bought 1 ${item.name}'),
          action: SnackBarAction(
            label: 'Undo',
            // A correction, not a negative restock: this reverses a bookkeeping
            // mistake rather than describing a return to the shop. Neither
            // source feeds the consumption rate, so the pair cancels cleanly.
            onPressed: () => repository.adjustQuantity(
              item.id,
              -1,
              AdjustmentSource.correction,
              now: now?.call(),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Item>>(
    stream: stream,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <Item>[];
      if (items.isEmpty) {
        return EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          message: emptyMessage,
        );
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final tile = ItemTile(
            item: item,
            onTap: () => _open(context, item),
          );
          if (!showRestock) return tile;
          return Row(
            children: [
              Expanded(child: tile),
              IconButton(
                onPressed: () => _bought(context, item),
                icon: const Icon(Icons.add_shopping_cart),
                tooltip: 'Bought one',
              ),
            ],
          );
        },
      );
    },
  );
}
