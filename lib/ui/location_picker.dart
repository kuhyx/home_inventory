/// Choosing a place from the tree.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/location.dart';
import 'package:home_inventory/models/location_tree.dart';
import 'package:home_inventory/ui/theme.dart';

/// What a picker returned: a place, or the explicit "no place" choice.
///
/// A wrapper rather than a bare `Location?`, because a dismissed sheet and a
/// deliberate "top level" / "nowhere" both arrive as null otherwise, and those
/// mean opposite things: leave it alone versus unfile it.
@immutable
class LocationChoice {
  /// Creates a choice for [location], or the root when null.
  const LocationChoice(this.location);

  /// The chosen place, or null for "top level" / "not filed anywhere".
  final Location? location;

  /// The chosen id, or empty for the root.
  String get id => location?.id ?? '';
}

/// Asks the user to pick a place, returning null when they dismiss it.
///
/// One picker serves moving a location, filtering the item list, and setting
/// an item's place, so the tree behaves identically in all three.
///
/// [excludeSubtreeOf] greys out a branch — used when moving a place, since a
/// place cannot live inside itself.
Future<LocationChoice?> showLocationPicker(
  BuildContext context, {
  required ItemRepository repository,
  required String title,
  String? excludeSubtreeOf,
  String rootLabel = 'Top level',
}) {
  final blocked = excludeSubtreeOf == null
      ? const <String>{}
      : repository.subtreeIds(excludeSubtreeOf);
  return showModalBottomSheet<LocationChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LocationPickerSheet(
      repository: repository,
      title: title,
      blocked: blocked,
      rootLabel: rootLabel,
    ),
  );
}

class _LocationPickerSheet extends StatelessWidget {
  const _LocationPickerSheet({
    required this.repository,
    required this.title,
    required this.blocked,
    required this.rootLabel,
  });

  final ItemRepository repository;
  final String title;
  final Set<String> blocked;
  final String rootLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <LocationTreeNode>[];
    void walk(List<LocationTreeNode> nodes) {
      for (final node in nodes) {
        rows.add(node);
        walk(node.children);
      }
    }

    walk(repository.locationTree());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(rootLabel),
              onTap: () =>
                  Navigator.of(context).pop(const LocationChoice(null)),
            ),
            const Divider(),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'No places yet. Add one on the Locations tab.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final node = rows[index];
                        final disabled = blocked.contains(node.id);
                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: AppSpacing.md + AppSpacing.lg * node.depth,
                            right: AppSpacing.md,
                          ),
                          title: Text(node.name),
                          enabled: !disabled,
                          onTap: disabled
                              ? null
                              : () => Navigator.of(
                                  context,
                                ).pop(LocationChoice(node.location)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
