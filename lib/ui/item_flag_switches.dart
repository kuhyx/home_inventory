/// The two shopping-list flags, as one block.
library;

import 'package:flutter/material.dart';

/// "I want this" and "I could sell this", side by side in the form.
///
/// One widget rather than two loose switches: they are the pair that decides
/// which of the two shopping lists an item shows up on, and keeping their
/// wording together is what stops one drifting from the other.
class ItemFlagSwitches extends StatelessWidget {
  /// Creates the block.
  const ItemFlagSwitches({
    required this.wanted,
    required this.sellable,
    required this.onWantedChanged,
    required this.onSellableChanged,
    super.key,
  });

  /// Whether the item belongs on the buy list regardless of stock.
  final bool wanted;

  /// Whether the item belongs on the sell list.
  final bool sellable;

  /// Called with the new [wanted] value.
  final ValueChanged<bool> onWantedChanged;

  /// Called with the new [sellable] value.
  final ValueChanged<bool> onSellableChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SwitchListTile(
        key: const Key('item_flag_wanted'),
        value: wanted,
        onChanged: onWantedChanged,
        secondary: const Icon(Icons.star_outline),
        title: const Icon(Icons.star, semanticLabel: 'I want this'),
      ),
      SwitchListTile(
        key: const Key('item_flag_sellable'),
        value: sellable,
        onChanged: onSellableChanged,
        secondary: const Icon(Icons.sell_outlined),
        title: const Icon(Icons.sell, semanticLabel: 'I could sell this'),
      ),
    ],
  );
}
