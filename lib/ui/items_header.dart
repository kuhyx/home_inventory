/// The item list's header: search, filter, sort, scan, sync.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/ui/summary_strip.dart';
import 'package:home_inventory/ui/theme.dart';

/// The row of controls above the item list.
///
/// This screen has no `AppBar` — the search field is the header — so every
/// action that would live in one lives here instead.
class ItemsHeader extends StatelessWidget {
  /// Creates the header.
  const ItemsHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.activeFilterCount,
    required this.onOpenFilter,
    required this.sort,
    required this.onSortSelected,
    required this.onScan,
    required this.onOpenSettings,
    super.key,
  });

  /// Controller for the search box, owned by the screen.
  final TextEditingController searchController;

  /// Called on every keystroke; the screen debounces.
  final ValueChanged<String> onSearchChanged;

  /// How many facets are restricted, for the badge.
  final int activeFilterCount;

  /// Opens the filter sheet.
  final VoidCallback onOpenFilter;

  /// The sort currently applied, ticked in the menu.
  final ItemSort sort;

  /// Called with the chosen sort.
  final ValueChanged<ItemSort> onSortSelected;

  /// Opens the code prompt that restocks by barcode.
  final VoidCallback onScan;

  /// Opens the sync settings screen.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          onPressed: onOpenFilter,
          // The badge counts *facets*, not selections, so three rooms read as
          // one restriction — which is how many taps it takes to undo them
          // from the sheet.
          icon: Badge(
            isLabelVisible: activeFilterCount > 0,
            label: Text('$activeFilterCount'),
            child: const Icon(Icons.filter_list),
          ),
          tooltip: 'Filter',
        ),
        PopupMenuButton<ItemSort>(
          onSelected: onSortSelected,
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
          itemBuilder: (_) => [
            for (final value in ItemSort.values)
              CheckedPopupMenuItem(
                value: value,
                checked: value == sort,
                child: Text(sortLabel(value)),
              ),
          ],
        ),
        IconButton(
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: 'Scan to restock',
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.sync),
          tooltip: 'Sync',
        ),
      ],
    ),
  );
}
