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
        value: wanted,
        onChanged: onWantedChanged,
        title: const Text('I want this'),
        subtitle: const Text('Keeps it on the buy list'),
      ),
      SwitchListTile(
        value: sellable,
        onChanged: onSellableChanged,
        title: const Text('I could sell this'),
      ),
    ],
  );
}
