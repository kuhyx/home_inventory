/// Folding the legacy `room`/`container` strings into real place records.
library;

import 'package:home_inventory/data/derived_ids.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/location.dart';
import 'package:meta/meta.dart';

/// What a migration pass would change: places to create, items to re-file.
@immutable
class MigrationPlan {
  /// Creates a plan.
  const MigrationPlan({required this.locations, required this.itemLocationIds});

  /// Places that need to exist, parents before children.
  final List<Location> locations;

  /// Item id → the location id it should be filed under.
  final Map<String, String> itemLocationIds;

  /// Whether this plan would change anything at all.
  bool get isEmpty => locations.isEmpty && itemLocationIds.isEmpty;
}

/// Plans the fold of legacy [items] strings into [Location] records.
///
/// Pure: same inputs, same plan, no clock beyond [now] and no storage. That is
/// what makes it safe to run on load, again after every sync, and on both
/// devices at once.
///
/// **Why this converges.** Every id here comes from [derivedLocationId], a
/// pure function of `(parentId, folded name)`. Two devices folding the same
/// `room: 'Kitchen'` therefore write records with the *same id* and the same
/// `name`/`parent_id` values; per-field last-writer-wins picks between two
/// identical values and the merge is a no-op. Only the clocks and `created_at`
/// can differ, which is cosmetic. So: run it twice, run it on two devices, run
/// it after a sync that dragged in un-migrated items from an old build — the
/// log converges either way. That is the same bar `dropAncientAdjustments` had
/// to clear, and for the same reason.
///
/// Items already carrying an [Item.locationId] are left alone, which is what
/// makes a second pass a no-op. The legacy strings are deliberately *not*
/// cleared: a device still on the old build reads them, and it is the only
/// thing it can read. They go away once every device is updated.
MigrationPlan planLocationMigration(
  Iterable<Item> items,
  Iterable<Location> existing,
  DateTime now,
) {
  final known = {for (final location in existing) location.id};
  final locations = <String, Location>{};
  final itemLocationIds = <String, String>{};

  Location build(String id, String name, String? parentId) => Location(
    id: id,
    name: name.trim(),
    parentId: parentId,
    sortKey: 0,
    createdAt: now,
    updatedAt: now,
  );

  for (final item in items) {
    // Already filed, or nothing to file it under.
    if (item.locationId.isNotEmpty) continue;
    final room = item.room.trim();
    if (room.isEmpty) continue;

    final roomId = derivedLocationId(null, room);
    if (!known.contains(roomId)) {
      locations.putIfAbsent(roomId, () => build(roomId, room, null));
    }

    final container = item.container.trim();
    if (container.isEmpty) {
      itemLocationIds[item.id] = roomId;
      continue;
    }

    final containerId = derivedLocationId(roomId, container);
    if (!known.contains(containerId)) {
      locations.putIfAbsent(
        containerId,
        () => build(containerId, container, roomId),
      );
    }
    itemLocationIds[item.id] = containerId;
  }

  // Parents before children, so a consumer writing them in order never has a
  // child pointing at a location that does not exist yet.
  final ordered = locations.values.toList()
    ..sort((a, b) {
      if (a.parentId == null && b.parentId != null) return -1;
      if (a.parentId != null && b.parentId == null) return 1;
      return a.id.compareTo(b.id);
    });

  return MigrationPlan(locations: ordered, itemLocationIds: itemLocationIds);
}
