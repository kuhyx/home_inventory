// coverage:ignore-file
// Bootstrap only: resolves real platform storage and calls runApp, neither of
// which is reachable from a headless test. All testable logic lives behind
// `openRepository()`'s covered `openRepositoryIn(path)` counterpart.

/// Entry point for the home inventory app.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/repository_factory.dart';
import 'package:home_inventory/screens/home_shell.dart';
import 'package:home_inventory/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await openRepository();
  runApp(HomeInventoryApp(repository: repository));
}

/// The application root: theme wiring plus the home surface.
class HomeInventoryApp extends StatelessWidget {
  /// Creates the app root.
  const HomeInventoryApp({required this.repository, super.key});

  /// The single store, passed down by constructor rather than an injector.
  final ItemRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: HomeShell(repository: repository),
    );
  }
}
