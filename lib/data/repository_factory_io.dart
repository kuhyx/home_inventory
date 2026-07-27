import 'dart:io';

import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Opens the inventory store on a `dart:io` platform (Android).
// coverage:ignore-start
// Resolves the real per-platform application-support directory, so it cannot
// run under test; [openRepositoryIn] holds all the logic and is covered.
Future<ItemRepository> openRepository() async {
  final dir = await getApplicationSupportDirectory();
  return openRepositoryIn(dir.path);
}
// coverage:ignore-end

/// Opens the inventory store rooted at [dirPath].
///
/// Split out from [openRepository] so tests can drive it against a temporary
/// directory without going through `path_provider`.
Future<ItemRepository> openRepositoryIn(String dirPath) async {
  final persistence = FileLogPersistence(
    File(p.join(dirPath, ItemRepository.logFileName)),
  );

  final prefs = await SharedPreferences.getInstance();
  var nodeId = prefs.getString(ItemRepository.kNodeId) ?? '';
  if (nodeId.isEmpty) {
    // A per-install uuid rather than a fixed "phone"/"desktop" constant: two
    // devices sharing a node id overwrite each other's pushed file on every
    // sync tick, and a uuid keeps a third device safe by construction.
    nodeId = const Uuid().v4();
    await prefs.setString(ItemRepository.kNodeId, nodeId);
  }
  return ItemRepository.openWith(persistence: persistence, nodeId: nodeId);
}
