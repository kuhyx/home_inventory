/// A place things live, at any depth.
library;

import 'package:meta/meta.dart';

/// One node in the arbitrarily-deep place tree.
///
/// Persisted as its own CRDT record rather than derived from strings on each
/// item, which is what lets a room exist before anything is in it and lets a
/// rename be one write instead of a rewrite of every item filed there.
///
/// `@immutable` comes from `package:meta`, never `package:flutter/foundation`:
/// the models are reachable from `tool/sync_smoke.dart`, which runs under
/// plain `dart run` and cannot load the Flutter SDK.
@immutable
class Location {
  /// Creates a location. Every field is required so a new persisted field can
  /// never be silently forgotten at a call site.
  const Location({
    required this.id,
    required this.name,
    required this.parentId,
    required this.sortKey,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable identifier, also the CRDT record id.
  ///
  /// Derived from `(parentId, folded name)` — see `derivedLocationId`. Keyed
  /// to the name this location was born with, so it survives a rename.
  final String id;

  /// What the place is called, e.g. `najwyższa półka`.
  final String name;

  /// The enclosing place, or null when this sits at the top level.
  final String? parentId;

  /// Manual ordering among siblings; ties break on name.
  ///
  /// A double rather than an int so a future drag-to-reorder can insert
  /// between two neighbours without renumbering the whole sibling list.
  final double sortKey;

  /// When the place was first created.
  final DateTime createdAt;

  /// When the place was last edited.
  final DateTime updatedAt;

  /// Whether this sits at the top of the tree.
  bool get isRoot => parentId == null;

  /// Returns a copy with the given fields replaced.
  ///
  /// A null argument means "leave unchanged", so moving a location *to* the
  /// top level needs the explicit [clearParentId] flag rather than a null
  /// [parentId], which would be indistinguishable from "don't touch it".
  Location copyWith({
    String? name,
    String? parentId,
    bool clearParentId = false,
    double? sortKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Location(
    id: id,
    name: name ?? this.name,
    parentId: clearParentId ? null : (parentId ?? this.parentId),
    sortKey: sortKey ?? this.sortKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  String toString() => 'Location(id: $id, name: $name, parentId: $parentId)';
}
