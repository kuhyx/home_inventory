/// Filing an item that predates the places tree, from its own old strings.
library;

import 'package:home_inventory/data/item_repository.dart';

/// Creates the places [room] and [container] name, returning the deepest id.
///
/// The ids are the same ones `planLocationMigration` would derive —
/// `createLocation` is a pure function of (parent, folded name) — so filing an
/// item here, the moment it is edited, converges with a device that gets there
/// via the migration instead. Empty when the item names no room at all.
Future<String> fileLegacyStrings(
  ItemRepository repository, {
  required String room,
  required String container,
  required DateTime at,
}) async {
  final roomName = room.trim();
  if (roomName.isEmpty) return '';
  final roomPlace = await repository.createLocation(name: roomName, now: at);
  final containerName = container.trim();
  if (containerName.isEmpty) return roomPlace.id;
  final inner = await repository.createLocation(
    name: containerName,
    parentId: roomPlace.id,
    now: at,
  );
  return inner.id;
}

/// The legacy `room`/`container` pair a place path maps onto.
///
/// Both forms keep writing these for as long as a device on an older build
/// might read them: that build knows nothing of `location_id`, and an empty
/// `room` there reads as an item that lost its place. The root of the path is
/// the room; everything below it is the container, joined, because the old
/// shape has exactly two levels and the tree has any number.
({String room, String container}) legacyStringsFor(List<String> path) => (
  room: path.isEmpty ? '' : path.first,
  container: path.length > 1 ? path.skip(1).join(' › ') : '',
);
