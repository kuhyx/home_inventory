/// The root surface, and the seam where extra destinations will attach.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/items_screen.dart';

/// Root surface of the app.
///
/// Currently a single destination, so there is deliberately no
/// [NavigationBar]: that widget asserts it has at least two destinations, and
/// the assert is stripped from release builds — a one-destination bar
/// therefore renders fine on a device and crashes only in debug. It arrives
/// together with the locations and shopping tabs, at which point this becomes
/// an [IndexedStack] so each tab keeps its own scroll position and in-flight
/// search across switches.
class HomeShell extends StatelessWidget {
  /// Creates the shell.
  const HomeShell({required this.repository, this.now, super.key});

  /// Store shared by every destination.
  final ItemRepository repository;

  /// Injectable clock, passed to anything that writes.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) =>
      ItemsScreen(repository: repository, now: now);
}
