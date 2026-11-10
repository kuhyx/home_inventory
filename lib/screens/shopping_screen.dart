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
        title: const Icon(
          Icons.shopping_cart_outlined,
          semanticLabel: 'Shopping',
        ),
        bottom: const TabBar(
          tabs: [
            Tab(
              key: Key('tab_to_buy'),
              icon: Icon(Icons.shopping_bag_outlined, semanticLabel: 'To buy'),
            ),
            Tab(
              key: Key('tab_to_sell'),
              icon: Icon(Icons.sell_outlined, semanticLabel: 'To sell'),
            ),
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
            emptyLabel: 'Nothing to buy',
            showRestock: true,
          ),
          _ItemList(
            stream: repository.watchSellable(),
            repository: repository,
            now: now,
            emptyIcon: Icons.sell_outlined,
            emptyLabel: 'Nothing to sell',
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
    required this.emptyLabel,
    required this.showRestock,
  });

  final Stream<List<Item>> stream;
  final ItemRepository repository;
  final DateTime Function()? now;
  final IconData emptyIcon;

  /// Spoken-only label for the empty state.
  final String emptyLabel;
  final bool showRestock;

  Future<void> _open(BuildContext context, Item item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(repository: repository, itemId: item.id, now: now),
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
          key: const Key('snack_bought'),
          content: Row(children: [const Icon(Icons.check), Text(item.name)]),
          action: SnackBarAction(
            label: '↶',
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
          badge: Icons.check,
          semanticLabel: emptyLabel,
        );
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final tile = ItemTile(
            item: item,
            locationLabel: repository.locationLabelFor(item),
            onTap: () => _open(context, item),
          );
          if (!showRestock) return tile;
          return Row(
            children: [
              Expanded(child: tile),
              IconButton(
                key: const Key('btn_bought_one'),
                onPressed: () => _bought(context, item),
                icon: const Icon(
                  Icons.add_shopping_cart,
                  semanticLabel: 'Bought one',
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
