/// The root surface: three destinations over one repository.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/items_screen.dart';
import 'package:home_inventory/screens/locations_screen.dart';
import 'package:home_inventory/screens/shopping_screen.dart';

/// Root surface of the app.
///
/// An [IndexedStack] rather than a swapped child, so each tab keeps its scroll
/// position, its expanded rooms and its in-flight search across switches —
/// going to Shopping and back must not throw away what was typed.
///
/// It also owns the items tab's requested filter, because the locations tab
/// writes to it: tapping a container has to land on a filtered item list, and
/// one child cannot reach across to a sibling.
class HomeShell extends StatefulWidget {
  /// Creates the shell.
  const HomeShell({required this.repository, this.now, super.key});

  /// Store shared by every destination.
  final ItemRepository repository;

  /// Injectable clock, passed to anything that writes.
  final DateTime Function()? now;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  ItemFilter? _requestedFilter;

  /// Shows one place, and everything inside it, on the items tab.
  void _showLocation(String locationId) {
    setState(() {
      // Expanded to the whole subtree here, because the filter matches ids
      // exactly: asking for "the hallway" and getting only the things loose in
      // it, while everything on its shelves stays hidden, would read as a bug.
      _requestedFilter = ItemFilter(
        locationIds: widget.repository.subtreeIds(locationId),
      );
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: [
        ItemsScreen(
          repository: widget.repository,
          now: widget.now,
          requestedFilter: _requestedFilter,
        ),
        LocationsScreen(
          repository: widget.repository,
          onSelect: _showLocation,
        ),
        ShoppingScreen(repository: widget.repository, now: widget.now),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Items',
        ),
        NavigationDestination(
          icon: Icon(Icons.room_preferences_outlined),
          selectedIcon: Icon(Icons.room_preferences),
          label: 'Locations',
        ),
        NavigationDestination(
          icon: Icon(Icons.shopping_cart_outlined),
          selectedIcon: Icon(Icons.shopping_cart),
          label: 'Shopping',
        ),
      ],
    ),
  );
}
