/// "Where is it?" — the room → container tree.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/location_node.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/theme.dart';

/// Browsable two-level map of the house.
///
/// Read-only by design: it answers "where is it" and hands off to the items
/// list for anything else, so there is exactly one place that edits an item.
class LocationsScreen extends StatelessWidget {
  /// Creates the locations screen.
  const LocationsScreen({
    required this.repository,
    required this.onSelect,
    super.key,
  });

  /// Source of the tree.
  final ItemRepository repository;

  /// Called with the tapped room, and the container within it when the tap
  /// was on a container row. The shell turns that into a filtered items list.
  final void Function(String room, String? container) onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locations')),
      body: StreamBuilder<List<LocationNode>>(
        stream: repository.watchLocationTree(),
        builder: (context, snapshot) {
          final rooms = snapshot.data ?? const <LocationNode>[];
          if (rooms.isEmpty) {
            return const EmptyState(
              icon: Icons.room_preferences_outlined,
              title: 'No locations yet',
              message: 'Give an item a room and it will show up here.',
            );
          }
          return ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (context, index) =>
                _RoomTile(node: rooms[index], onSelect: onSelect),
          );
        },
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.node, required this.onSelect});

  final LocationNode node;
  final void Function(String room, String? container) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      // An item with no room still has to be reachable, or it is invisible on
      // the one screen whose whole job is finding things.
      title: Text(node.room.isEmpty ? 'No room' : node.room),
      subtitle: Text(
        _countLabel(node.itemCount),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        // Separate from the expand affordance: tapping the row should open the
        // room, not silently jump to another tab.
        onPressed: () => onSelect(node.room, null),
        icon: const Icon(Icons.arrow_forward),
        tooltip: 'Show everything in this room',
      ),
      children: [
        for (final container in node.containers)
          ListTile(
            contentPadding: const EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.md,
            ),
            title: Text(
              container.name.isEmpty ? 'Loose in the room' : container.name,
            ),
            trailing: Text(
              '${container.itemCount}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () => onSelect(node.room, container.name),
          ),
      ],
    );
  }

  static String _countLabel(int count) =>
      count == 1 ? '1 item' : '$count items';
}
