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
  const LocationChoice(this.location, {this.created = false});

  /// The chosen place, or null for "top level" / "not filed anywhere".
  final Location? location;

  /// Whether this place was made by the picker just now.
  ///
  /// The caller tells the user so, which is the difference between a place
  /// appearing because they meant it and a typo quietly becoming a new room.
  final bool created;

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
///
/// [allowCreate] adds a "new place" box at the bottom, filing what is typed
/// under [createParentId] (the top level when null). Only the item forms turn
/// it on: filing a thing is the moment a missing shelf is noticed, and making
/// the user leave the form for the Locations tab to add it is how a room ends
/// up as free text instead.
Future<LocationChoice?> showLocationPicker(
  BuildContext context, {
  required ItemRepository repository,
  required String title,
  String? excludeSubtreeOf,
  String rootLabel = 'Top level',
  bool allowCreate = false,
  String? createParentId,
  DateTime Function()? now,
}) {
  final blocked = excludeSubtreeOf == null
      ? const <String>{}
      : repository.subtreeIds(excludeSubtreeOf);
  return showModalBottomSheet<LocationChoice>(
    context: context,
    isScrollControlled: true,
    // Without this the route strips the top inset, and a tree deep enough to
    // fill the screen puts the title under the status bar — which is exactly
    // what a real phone showed once the create box made the sheet taller.
    useSafeArea: true,
    builder: (context) => _LocationPickerSheet(
      repository: repository,
      title: title,
      blocked: blocked,
      rootLabel: rootLabel,
      allowCreate: allowCreate,
      createParentId: createParentId,
      now: now,
    ),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.repository,
    required this.title,
    required this.blocked,
    required this.rootLabel,
    required this.allowCreate,
    required this.createParentId,
    required this.now,
  });

  final ItemRepository repository;
  final String title;
  final Set<String> blocked;
  final String rootLabel;
  final bool allowCreate;
  final String? createParentId;
  final DateTime Function()? now;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  /// Resolves the typed name to a place, making it only if it is new.
  ///
  /// `createLocation` is idempotent on the derived id, so this cannot mint a
  /// second "Korytarz" next to `korytarz` — the fold is part of the id. The
  /// existence check is therefore only about what to *tell* the user.
  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    final parentId = widget.createParentId;
    final existed = widget.repository.hasChildNamed(parentId, name);
    final location = await widget.repository.createLocation(
      name: name,
      parentId: parentId,
      now: widget.now?.call(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(LocationChoice(location, created: !existed));
  }

  /// Where a typed name would land, spelled out rather than implied.
  String get _createLabel {
    final parentId = widget.createParentId;
    if (parentId == null || parentId.isEmpty) return 'New room';
    return 'New place in ${widget.repository.pathLabel(parentId)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repository = widget.repository;
    final title = widget.title;
    final blocked = widget.blocked;
    final rootLabel = widget.rootLabel;
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
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.md,
          // Without this the create box sits under the keyboard it opened.
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
        ),
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
                        widget.allowCreate
                            ? 'No places yet. Type a name below to make one.'
                            : 'No places yet. Add one on the Locations tab.',
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
            if (widget.allowCreate) ...[
              const Divider(),
              TextField(
                controller: _newName,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _createLabel,
                  suffixIcon: IconButton(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    tooltip: 'Create it',
                  ),
                ),
                onSubmitted: (_) => _create(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
