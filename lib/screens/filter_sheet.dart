/// The sheet that narrows the item list down to one corner of the house.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/ui/location_picker.dart';
import 'package:home_inventory/ui/theme.dart';

/// Modal editor for an [ItemFilter].
///
/// Pops with the edited filter, or with null when dismissed — so the caller
/// can tell "cleared everything" apart from "changed my mind", which are the
/// same empty filter otherwise.
///
/// The chips come from what is actually in the inventory rather than a fixed
/// vocabulary: categories are free text, so there is no closed set to
/// enumerate. Places are the exception — they are real records, so they get a
/// tree picker instead of chips.
class FilterSheet extends StatefulWidget {
  /// Creates the sheet, starting from [initial].
  const FilterSheet({
    required this.repository,
    required this.initial,
    super.key,
  });

  /// Source of the available chip values.
  final ItemRepository repository;

  /// Filter to start from; edits are applied on top of it.
  final ItemFilter initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ItemFilter _filter = widget.initial;

  void _toggle<T>(Set<T> current, T value, void Function(Set<T>) apply) {
    final next = current.contains(value)
        ? (current.toSet()..remove(value))
        : (current.toSet()..add(value));
    setState(() => apply(next));
  }

  /// Label for the place facet: the deepest chosen place, plus a count when
  /// more than one branch is selected.
  String _placeLabel(ItemRepository repository) {
    final named = _filter.locationIds
        .map(repository.pathLabel)
        .where((label) => label.isNotEmpty)
        .toList();
    if (named.isEmpty) return 'Somewhere';
    // The selection is a whole subtree, so the shortest path is its root and
    // the only part worth showing.
    named.sort((a, b) => a.length.compareTo(b.length));
    return named.first;
  }

  Future<void> _pickPlace(ItemRepository repository) async {
    final choice = await showLocationPicker(
      context,
      repository: repository,
      title: 'Show things in',
      rootLabel: 'Anywhere',
    );
    if (choice == null) return;
    final place = choice.location;
    setState(() {
      _filter = _filter.copyWith(
        // Whole subtree, so "the hallway" includes its shelves.
        locationIds: place == null
            ? const <String>{}
            : repository.subtreeIds(place.id),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repository = widget.repository;
    // The place facet is a picker rather than a chip row: at arbitrary depth a
    // flat list of every shelf in the flat is unusable, and the chips could
    // not show which shelf belongs to which cupboard anyway.
    final placeLabel = _filter.locationIds.isEmpty
        ? 'Anywhere'
        : _placeLabel(repository);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Filter', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  // Clears the facets but keeps the search text: the box is
                  // still visibly full, so wiping it from here would look like
                  // the app lost the query.
                  onPressed: () => setState(() {
                    _filter = ItemFilter(query: _filter.query);
                  }),
                  child: const Text('Clear all'),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChipGroup(
                      label: 'Stock',
                      chips: [
                        for (final state in StockState.values)
                          _Chip(
                            label: _stockLabel(state),
                            selected: _filter.stock.contains(state),
                            onSelected: () => _toggle(
                              _filter.stock,
                              state,
                              (next) => _filter = _filter.copyWith(stock: next),
                            ),
                          ),
                      ],
                    ),
                    _ChipGroup(
                      label: 'Flags',
                      chips: [
                        for (final flag in ItemFlag.values)
                          _Chip(
                            label: _flagLabel(flag),
                            selected: _filter.flags.contains(flag),
                            onSelected: () => _toggle(
                              _filter.flags,
                              flag,
                              (next) => _filter = _filter.copyWith(flags: next),
                            ),
                          ),
                      ],
                    ),
                    _PlaceFacet(
                      label: placeLabel,
                      selected: _filter.locationIds.isNotEmpty,
                      onPick: () => _pickPlace(repository),
                      onClear: () => setState(
                        () => _filter = _filter.copyWith(
                          locationIds: const <String>{},
                        ),
                      ),
                    ),
                    _ChipGroup(
                      label: 'Categories',
                      chips: [
                        for (final category in repository.knownCategories())
                          _Chip(
                            label: category,
                            selected: _filter.categories.contains(category),
                            onSelected: () => _toggle(
                              _filter.categories,
                              category,
                              (next) => _filter = _filter.copyWith(
                                categories: next,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_filter),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _stockLabel(StockState state) => switch (state) {
    StockState.ok => 'In stock',
    StockState.low => 'Low',
    StockState.out => 'Out',
  };

  static String _flagLabel(ItemFlag flag) => switch (flag) {
    ItemFlag.wanted => 'Wanted',
    ItemFlag.sellable => 'Sellable',
  };
}

/// A labelled row of chips, hidden entirely when it has nothing to offer.
/// The "Place" facet: a button opening the tree picker, plus a clear.
///
/// Not a chip row like the other facets, because the places form a tree and a
/// flat row of every shelf in the flat says nothing about which cupboard each
/// one is in.
class _PlaceFacet extends StatelessWidget {
  const _PlaceFacet({
    required this.label,
    required this.selected,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final bool selected;
  final VoidCallback onPick;
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

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.label, required this.chips});

  final String label;
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}
