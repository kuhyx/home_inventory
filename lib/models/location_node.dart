/// The two-level room → container tree behind the "where is it" screen.
library;

/// One container within a room, with how many items are in it.
class ContainerNode {
  /// Creates a container node.
  const ContainerNode({required this.name, required this.itemCount});

  /// Container name; empty means "loose in the room, no container given".
  final String name;

  /// How many items sit in this container.
  final int itemCount;
}

/// One room, with its containers.
class LocationNode {
  /// Creates a room node.
  const LocationNode({
    required this.room,
    required this.containers,
    required this.itemCount,
  });

  /// Room name; empty means "no room given yet".
  final String room;

  /// Containers in this room, busiest first.
  final List<ContainerNode> containers;

  /// Total items in the room, across every container.
  final int itemCount;
}
