/// The main list: what you have, and where.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/inventory_summary.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
import 'package:home_inventory/screens/quick_add_sheet.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/item_tile.dart';
import 'package:home_inventory/ui/theme.dart';

/// Searchable list of everything owned.
class ItemsScreen extends StatefulWidget {
  /// Creates the list screen.
  const ItemsScreen({required this.repository, this.now, super.key});

  /// Store to read.
  final ItemRepository repository;

  /// Injectable clock, passed down to anything that writes.
  final DateTime Function()? now;

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
  ItemFilter _filter = const ItemFilter();
  // Becomes mutable when the filter sheet lands; until then the default sort
  // is the only one reachable from the UI.
  final ItemSort _sort = ItemSort.updatedDesc;
  late Stream<List<Item>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository.watchItems(sort: _sort, filter: _filter);
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
              '${summary.total} items · ${summary.toBuy} to buy',
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
