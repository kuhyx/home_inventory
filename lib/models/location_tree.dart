/// The resolved place tree behind the "where is it" screen.
library;

import 'package:home_inventory/models/location.dart';
import 'package:meta/meta.dart';

/// One [Location] with its children and item counts resolved.
///
/// Derived on read rather than stored: the counts depend on every item in the
/// log, so a stored copy would be a second source of truth that any quantity
/// or location edit could leave stale.
@immutable
class LocationTreeNode {
  /// Creates a resolved tree node.
  const LocationTreeNode({
    required this.location,
    required this.children,
    required this.directItemCount,
    required this.totalItemCount,
    required this.depth,
  });

  /// The place itself.
  final Location location;

  /// Places directly inside this one, already ordered.
  final List<LocationTreeNode> children;

  /// Items filed at exactly this place, not counting its children.
  final int directItemCount;

  /// Items filed here or anywhere below.
  ///
  /// The number worth showing on a collapsed row: a cupboard reading "0 items"
  /// because everything sits on its shelves is a lie the user has to expand to
  /// disprove.
  final int totalItemCount;

  /// How deep this sits; 0 at the top level. Drives row indentation.
  final int depth;

  /// This node's id, for brevity at call sites.
  String get id => location.id;

  /// This node's name, for brevity at call sites.
  String get name => location.name;
}
