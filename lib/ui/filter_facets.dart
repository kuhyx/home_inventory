/// The facet controls the filter sheet is built out of.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// The "Place" facet: a button opening the tree picker, plus a clear.
///
/// Not a chip row like the other facets, because the places form a tree and a
/// flat row of every shelf in the flat says nothing about which cupboard each
/// one is in.
class PlaceFacet extends StatelessWidget {
  /// Creates the facet.
  const PlaceFacet({
    required this.label,
    required this.selected,
    required this.onPick,
    required this.onClear,
    super.key,
  });

  /// The chosen place's path, or "Anywhere".
  final String label;

  /// Whether a place is chosen, which is what shows the clear button.
  final bool selected;

  /// Opens the tree picker.
  final VoidCallback onPick;

  /// Drops the place restriction.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Place',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.place_outlined),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              if (selected)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  tooltip: 'Anywhere',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled row of chips, hidden entirely when it has nothing to offer.
class ChipGroup extends StatelessWidget {
  /// Creates the group.
  const ChipGroup({required this.label, required this.chips, super.key});

  /// Heading above the chips.
  final String label;

  /// The chips themselves; an empty list hides the whole group.
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    // An empty group is worse than no group: a "Categories" heading over blank
    // space reads as a loading failure rather than "you have not used any".
    if (chips.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: chips,
          ),
        ],
      ),
    );
  }
}

/// One value inside a [ChipGroup].
class FacetChip extends StatelessWidget {
  /// Creates the chip.
  const FacetChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// What the chip reads.
  final String label;

  /// Whether this value is currently restricting the list.
  final bool selected;

  /// Toggles this value.
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}
