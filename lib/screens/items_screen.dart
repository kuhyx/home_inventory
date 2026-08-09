/// The main list: what you have, and where.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/inventory_summary.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/filter_sheet.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
import 'package:home_inventory/screens/quick_add_sheet.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/item_tile.dart';
import 'package:home_inventory/ui/theme.dart';

/// Searchable list of everything owned.
class ItemsScreen extends StatefulWidget {
  /// Creates the list screen.
  const ItemsScreen({
    required this.repository,
    this.now,
    this.requestedFilter,
    super.key,
  });

  /// Store to read.
  final ItemRepository repository;

  /// Injectable clock, passed down to anything that writes.
  final DateTime Function()? now;

  /// A filter pushed in from another tab — the locations screen tapping a
  /// room or container. Adopted whenever it is a *different instance*.
  ///
  /// Identity, deliberately, not value equality. The shell rebuilds this
  /// widget on every tab switch while handing over the same object, so
  /// identity skips those. But tapping the same room twice is a genuine second
  /// request — the user may have cleared the filter in between — and it
  /// produces a fresh, value-equal instance. Comparing by `==` would swallow
  /// exactly that case and leave the tap doing nothing.
  final ItemFilter? requestedFilter;

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  /// How long to wait after the last keystroke before re-querying.
  ///
  /// Public so a widget test can pump exactly past it instead of guessing.
  static const searchDebounce = Duration(milliseconds: 250);

  final _search = TextEditingController();
  Timer? _debounce;
  late ItemFilter _filter = widget.requestedFilter ?? const ItemFilter();
  ItemSort _sort = ItemSort.updatedDesc;
  late Stream<List<Item>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository.watchItems(sort: _sort, filter: _filter);
  }

  @override
  void didUpdateWidget(ItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.requestedFilter;
    if (requested == null || identical(requested, oldWidget.requestedFilter)) {
      return;
    }
    // A location jump replaces the whole query context, search text included:
    // keeping a stale search term on top of a new room is the one combination
    // that reliably produces an empty list with no visible reason why.
    _debounce?.cancel();
    _search.clear();
    _filter = requested;
    _requery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _requery() {
    setState(() {
      _stream = widget.repository.watchItems(sort: _sort, filter: _filter);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      _filter = _filter.copyWith(query: value);
      _requery();
    });
  }

  Future<void> _openFilter() async {
    final edited = await showModalBottomSheet<ItemFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        repository: widget.repository,
        initial: _filter,
      ),
    );
    // Null means dismissed, which is not the same as an empty filter: the
    // sheet returns a filter only when Apply was pressed.
    if (edited == null) return;
    _filter = edited;
    _requery();
  }

  void _setSort(ItemSort sort) {
    _sort = sort;
    _requery();
  }

  Future<void> _add() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickAddSheet(
        repository: widget.repository,
        now: widget.now,
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          repository: widget.repository,
          now: widget.now,
        ),
      ),
    );
  }

  Future<void> _open(Item item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailScreen(
          repository: widget.repository,
          itemId: item.id,
          now: widget.now,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // There is no AppBar on this screen (the search field is the header), so
      // without SafeArea the field renders underneath the status bar — which
      // is exactly what happened on the first device build.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        labelText: 'Search',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    onPressed: _openFilter,
                    // The badge counts *facets*, not selections, so three
                    // rooms read as one restriction — which is how many taps
                    // it takes to undo them from the sheet.
                    icon: Badge(
                      isLabelVisible: _filter.activeCount > 0,
                      label: Text('${_filter.activeCount}'),
                      child: const Icon(Icons.filter_list),
                    ),
                    tooltip: 'Filter',
                  ),
                  PopupMenuButton<ItemSort>(
                    onSelected: _setSort,
                    icon: const Icon(Icons.sort),
                    tooltip: 'Sort',
                    itemBuilder: (_) => [
                      for (final sort in ItemSort.values)
                        CheckedPopupMenuItem(
                          value: sort,
                          checked: sort == _sort,
                          child: Text(_sortLabel(sort)),
                        ),
                    ],
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.sync),
                    tooltip: 'Sync',
                  ),
                ],
              ),
            ),
            _SummaryStrip(repository: widget.repository),
            Expanded(
              child: StreamBuilder<List<Item>>(
                stream: _stream,
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <Item>[];
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: _filter.isEmpty
                          ? 'Nothing here yet'
                          : 'No matches',
                      message: _filter.isEmpty
                          ? 'Tap + to add the first thing you own.'
                          : 'Try a different search.',
                    );
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => ItemTile(
                      item: items[index],
                      locationLabel: widget.repository.locationLabelFor(
                        items[index],
                      ),
                      onTap: () => _open(items[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: 'Add an item',
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _sortLabel(ItemSort sort) => switch (sort) {
  ItemSort.updatedDesc => 'Recently changed',
  ItemSort.nameAsc => 'Name (A-Z)',
  ItemSort.createdDesc => 'Newest first',
  ItemSort.quantityAsc => 'Fewest first',
  ItemSort.locationAsc => 'By location',
  ItemSort.lowStockFirst => 'Running low first',
};

/// One-line headline counts above the list.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.repository});

  final ItemRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<InventorySummary>(
      stream: repository.watchSummary(),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? InventorySummary.empty;
        if (summary.total == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${summary.total} ${summary.total == 1 ? 'item' : 'items'}'
              ' · ${summary.toBuy} to buy',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
