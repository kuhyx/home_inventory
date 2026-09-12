/// The places half of the repository: the tree, and everything that moves
/// things around inside it.
///
/// A `part` carrying a public extension, so call sites stay
/// `repository.locationTree()` while the private store stays private. The
/// tree rules — derived ids, cycles broken on read, deletes that never
/// cascade — are all here rather than spread across the file.
part of 'item_repository.dart';

/// Everything about places: the tree, paths, and the writes that shape it.
extension LocationQueries on ItemRepository {
  /// Every live place, in no particular order.
  List<Location> listLocations() => _liveLocations().toList();

  /// [listLocations] as a stream that re-emits on every write.
  Stream<List<Location>> watchLocations() => _watch(listLocations);

  /// The place with [id], or null if absent or deleted.
  Location? location(String id) {
    final record = _store.get(id);
    if (record == null || record.deleted) return null;
    if (!isLocationRecord(record)) return null;
    return _toLocation(record);
  }

  /// The whole place tree, with item counts, deepest structure intact.
  ///
  /// **Cycles are handled here, not only at the writer.** Under CRDT merge a
  /// cycle is not hypothetical: this device moves A under B while another
  /// moves B under A, each write wins its own field, and the merged graph has
  /// a two-node loop that a naive walk would follow forever. So the tree is
  /// built by walking down from the roots with a visited set, and anything
  /// never reached — a cycle, or a child of a deleted parent — is re-attached
  /// at the top level rather than vanishing. That rule is a pure function of
  /// the merged log, so both devices show the same tree.
  List<LocationTreeNode> locationTree() {
    final locations = {for (final l in _liveLocations()) l.id: l};

    final direct = <String, int>{};
    for (final item in _liveItems()) {
      if (item.locationId.isEmpty) continue;
      if (!locations.containsKey(item.locationId)) continue;
      direct.update(item.locationId, (n) => n + 1, ifAbsent: () => 1);
    }

    final childIds = <String?, List<String>>{};
    for (final entry in locations.entries) {
      final parent = entry.value.parentId;
      // A parent that is gone (tombstoned, or never synced) makes this a root,
      // so deleting a cupboard never takes its shelves out of sight with it.
      final resolved = parent != null && locations.containsKey(parent)
          ? parent
          : null;
      childIds.putIfAbsent(resolved, () => <String>[]).add(entry.key);
    }

    final visited = <String>{};

    List<LocationTreeNode> build(String? parentId, int depth) {
      final ids = childIds[parentId] ?? const <String>[];
      final nodes = <LocationTreeNode>[];
      for (final id in ids) {
        if (!visited.add(id)) continue;
        final children = build(id, depth + 1);
        final own = direct[id] ?? 0;
        nodes.add(
          LocationTreeNode(
            location: locations[id]!,
            children: children,
            directItemCount: own,
            totalItemCount:
                own + children.fold<int>(0, (sum, c) => sum + c.totalItemCount),
            depth: depth,
          ),
        );
      }
      return nodes..sort(_bySortKeyThenName);
    }

    final roots = build(null, 0);

    // Anything unreachable from a root is in a cycle. Re-root it so the user
    // can still see and fix it; dropping it would look like data loss.
    final stranded = locations.keys.where((id) => !visited.contains(id));
    for (final id in stranded.toList()) {
      if (visited.contains(id)) continue;
      visited.add(id);
      final children = build(id, 1);
      final own = direct[id] ?? 0;
      roots.add(
        LocationTreeNode(
          location: locations[id]!,
          children: children,
          directItemCount: own,
          totalItemCount:
              own + children.fold<int>(0, (sum, c) => sum + c.totalItemCount),
          depth: 0,
        ),
      );
    }

    return roots..sort(_bySortKeyThenName);
  }

  /// [locationTree] as a stream that re-emits on every write.
  Stream<List<LocationTreeNode>> watchLocationTree() => _watch(locationTree);

  /// The chain of names from the top down to [locationId].
  ///
  /// Empty when the id is unknown. Stops at a cycle rather than looping.
  List<String> pathOf(String locationId) {
    final names = <String>[];
    final seen = <String>{};
    var current = location(locationId);
    while (current != null && seen.add(current.id)) {
      names.insert(0, current.name);
      final parent = current.parentId;
      current = parent == null ? null : location(parent);
    }
    return names;
  }

  /// [pathOf] joined for display, e.g. `korytarz › szafka z lewej`.
  String pathLabel(String locationId) => pathOf(locationId).join(' › ');

  /// Where [item] is, as one label.
  ///
  /// Falls back to the legacy strings for an item the migration has not
  /// reached — one pulled in mid-sync from a device still on the old build,
  /// which would otherwise read as "nowhere" until the next app start.
  String locationLabelFor(Item item) => item.locationId.isEmpty
      ? item.legacyLocation
      : pathLabel(item.locationId);

  /// [locationId] plus every place beneath it.
  ///
  /// What "show me everything in the hallway" means: filtering by one id alone
  /// would miss everything on its shelves. Cycle-safe via the visited set.
  Set<String> subtreeIds(String locationId) {
    final byParent = <String, List<String>>{};
    for (final l in _liveLocations()) {
      final parent = l.parentId;
      if (parent != null) byParent.putIfAbsent(parent, () => []).add(l.id);
    }
    final ids = <String>{};
    void walk(String id) {
      // The visited set is what makes a merged-in cycle terminate here.
      if (!ids.add(id)) return;
      (byParent[id] ?? const <String>[]).forEach(walk);
    }

    walk(locationId);
    return ids;
  }

  static int _bySortKeyThenName(LocationTreeNode a, LocationTreeNode b) {
    final bySort = a.location.sortKey.compareTo(b.location.sortKey);
    if (bySort != 0) return bySort;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
