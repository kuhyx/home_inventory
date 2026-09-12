/// Making, renaming, moving and deleting places.
part of 'item_repository.dart';

/// The write side of the place tree.
///
/// Ids are derived rather than minted, so creating is idempotent across
/// devices; moving refuses a move into the mover's own subtree; deleting
/// never cascades. Each of those rules exists because the alternative loses
/// data under merge — see the notes on the methods.
extension LocationWrites on ItemRepository {
  /// Creates a place called [name] under [parentId].
  ///
  /// The id is derived, not minted, so this is idempotent: creating "Garage"
  /// twice — here and on another device, offline — yields one record, not two.
  /// Returns the existing place when it is already there.
  Future<Location> createLocation({
    required String name,
    String? parentId,
    double sortKey = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = derivedLocationId(parentId, name);
    final existing = location(id);
    if (existing != null) return existing;
    final created = Location(
      id: id,
      name: name.trim(),
      parentId: parentId,
      sortKey: sortKey,
      createdAt: at,
      updatedAt: at,
    );
    await _upsertFields(id, _fieldsForLocation(created, _store.nextHlc()));
    return created;
  }

  /// Whether [parentId] already holds a child called [name].
  ///
  /// Derived ids mean two same-named siblings would collapse onto one record,
  /// so the create/rename UI has to refuse the collision up front.
  bool hasChildNamed(String? parentId, String name, {String? ignoringId}) {
    final folded = foldKey(name);
    return _liveLocations().any(
      (l) =>
          l.id != ignoringId &&
          l.parentId == parentId &&
          foldKey(l.name) == folded,
    );
  }

  /// Renames [id]. The record id deliberately does not change with it.
  Future<void> renameLocation(String id, String name, {DateTime? now}) async {
    if (location(id) == null) return;
    final at = now ?? DateTime.now();
    final hlc = _store.nextHlc();
    await _upsertFields(id, {
      _fName: (name.trim(), hlc),
      _fUpdatedAt: (at.toIso8601String(), hlc),
    });
  }

  /// Re-parents [id] under [newParentId], or to the top level when null.
  ///
  /// Refuses a move into the mover's own subtree, which would orphan the
  /// branch. That check is the user-facing guard only — it cannot see a
  /// concurrent move on another device, which is why [locationTree] breaks
  /// cycles on read as well.
  Future<bool> moveLocation(
    String id,
    String? newParentId, {
    DateTime? now,
  }) async {
    if (location(id) == null) return false;
    if (id == newParentId) return false;
    if (newParentId != null && subtreeIds(id).contains(newParentId)) {
      return false;
    }
    final at = now ?? DateTime.now();
    final hlc = _store.nextHlc();
    await _upsertFields(id, {
      _fParentId: (newParentId, hlc),
      _fUpdatedAt: (at.toIso8601String(), hlc),
    });
    return true;
  }

  /// Deletes [id], leaving its children and items in place.
  ///
  /// Never cascades. A sticky CRDT delete plus a cascade means one mis-tap on
  /// a phone removes a whole wing of the tree on every device, with no undo;
  /// orphaned children resurface at the top level instead, and items filed in
  /// the deleted place read as unfiled.
  Future<void> deleteLocation(String id) => _store.delete(id);

  /// How many live items are filed at exactly [locationId].
  int itemCountAt(String locationId) =>
      _liveItems().where((i) => i.locationId == locationId).length;

  /// The place most things are filed in, or empty when nothing is filed.
  ///
  /// The quick-add default. It replaces `knownRooms().first`, which read the
  /// legacy `room` string: now that the forms file items as records, that
  /// string stops being written and the old default would have decayed to
  /// nothing as the pre-places items aged out.
  String mostUsedLocationId() {
    final counts = <String, int>{};
    for (final item in _liveItems()) {
      if (item.locationId.isEmpty) continue;
      if (location(item.locationId) == null) continue;
      counts.update(item.locationId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return '';
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        // Ties break on id so the default cannot flip between two equally
        // busy shelves from one rebuild to the next.
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return ranked.first;
  }

  /// The place a subtree selection was rooted at — the shallowest of [ids].
  ///
  /// [subtreeIds] returns an unordered set, so "which place did the user
  /// actually tap" is not recoverable from a filter directly. It is always
  /// the shallowest member; ties break on id, and an id with no live record
  /// is skipped. Empty when [ids] names nothing that exists.
  String rootOfSelection(Set<String> ids) {
    var best = '';
    var bestDepth = 0;
    for (final id in ids) {
      final depth = pathOf(id).length;
      if (depth == 0) continue;
      final better =
          best.isEmpty ||
          depth < bestDepth ||
          (depth == bestDepth && id.compareTo(best) < 0);
      if (better) {
        best = id;
        bestDepth = depth;
      }
    }
    return best;
  }
}
