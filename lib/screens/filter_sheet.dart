/// The sheet that narrows the item list down to one corner of the house.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/ui/filter_facets.dart';
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
                    ChipGroup(
                      label: 'Stock',
                      chips: [
                        for (final state in StockState.values)
                          FacetChip(
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
                    ChipGroup(
                      label: 'Best before',
                      chips: [
                        for (final state in FreshnessState.values)
                          FacetChip(
                            label: _freshnessLabel(state),
                            selected: _filter.freshness.contains(state),
                            onSelected: () => _toggle(
                              _filter.freshness,
                              state,
                              (next) =>
                                  _filter = _filter.copyWith(freshness: next),
                            ),
                          ),
                      ],
                    ),
                    ChipGroup(
                      label: 'Flags',
                      chips: [
                        for (final flag in ItemFlag.values)
                          FacetChip(
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
                    PlaceFacet(
                      label: placeLabel,
                      selected: _filter.locationIds.isNotEmpty,
                      onPick: () => _pickPlace(repository),
                      onClear: () => setState(
                        () => _filter = _filter.copyWith(
                          locationIds: const <String>{},
                        ),
                      ),
                    ),
                    ChipGroup(
                      label: 'Categories',
                      chips: [
                        for (final category in repository.knownCategories())
                          FacetChip(
                            label: category,
                            selected: _filter.categories.contains(category),
                            onSelected: () => _toggle(
                              _filter.categories,
                              category,
                              (next) =>
                                  _filter = _filter.copyWith(categories: next),
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

  static String _freshnessLabel(FreshnessState state) => switch (state) {
    FreshnessState.fresh => 'Fresh',
    FreshnessState.dueSoon => 'Due soon',
    FreshnessState.expired => 'Expired',
  };

  static String _flagLabel(ItemFlag flag) => switch (flag) {
    ItemFlag.wanted => 'Wanted',
    ItemFlag.sellable => 'Sellable',
  };
}
