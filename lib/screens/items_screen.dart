/// The main list: what you have, and where.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/filter_sheet.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
import 'package:home_inventory/screens/quick_add_sheet.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/item_tile.dart';
import 'package:home_inventory/ui/items_header.dart';
import 'package:home_inventory/ui/scan_restock.dart';
import 'package:home_inventory/ui/summary_strip.dart';

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
      builder: (_) =>
          FilterSheet(repository: widget.repository, initial: _filter),
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

  /// Adds an item, pre-filed where the list is currently pointed.
  ///
  /// The filter holds a whole subtree, so the place the user actually chose
  /// is its shallowest member — recovered here rather than threaded through
  /// the shell, so tapping a room on the Locations tab and picking one in the
  /// filter sheet both land on the same default. Nothing filtered falls back
  /// to the busiest place, inside the sheet.
  Future<void> _add() async {
    final anchor = widget.repository.rootOfSelection(_filter.locationIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickAddSheet(
        repository: widget.repository,
        initialLocationId: anchor.isEmpty ? null : anchor,
        now: widget.now,
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(repository: widget.repository, now: widget.now),
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

  Future<void> _scan() => promptScanRestock(
    context,
    repository: widget.repository,
    now: widget.now,
  );

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
            ItemsHeader(
              searchController: _search,
              onSearchChanged: _onSearchChanged,
              activeFilterCount: _filter.activeCount,
              onOpenFilter: _openFilter,
              sort: _sort,
              onSortSelected: _setSort,
              onScan: _scan,
              onOpenSettings: _openSettings,
            ),
            SummaryStrip(repository: widget.repository),
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
