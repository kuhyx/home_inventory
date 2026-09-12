/// The place field on the item forms: pick one, or make one.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/ui/location_picker.dart';

/// Shows where an item is filed, and opens the tree picker to change it.
///
/// Deliberately not a text field. Places are real records with a parent, so a
/// free-text box could only ever produce a string that some later migration
/// has to guess at — and it made "korytarz", "Korytarz" and "korytarz "
/// three different rooms. Typing is still available, but inside the picker,
/// where a typed name is created as a record and the user is told where it
/// landed.
class LocationField extends StatelessWidget {
  /// Creates the field.
  const LocationField({
    required this.repository,
    required this.locationId,
    required this.onChanged,
    this.label = 'Location',
    this.fallbackLabel = '',
    this.now,
    super.key,
  });

  /// Source of the tree, and where a new place gets written.
  final ItemRepository repository;

  /// Currently filed place, or empty for "not filed anywhere".
  final String locationId;

  /// Called with the chosen place id, empty for "not filed".
  final ValueChanged<String> onChanged;

  /// Field label.
  final String label;

  /// What to show when [locationId] is empty but the item still carries the
  /// legacy `room`/`container` strings — otherwise editing a pre-places item
  /// would read as "nowhere" and look like the app lost its location.
  final String fallbackLabel;

  /// Injectable clock, so tests get deterministic timestamps.
  final DateTime Function()? now;

  /// The path to show, deepest-last.
  String get _value {
    if (locationId.isNotEmpty) {
      final path = repository.pathLabel(locationId);
      if (path.isNotEmpty) return path;
    }
    return fallbackLabel.isEmpty ? 'Not filed anywhere' : fallbackLabel;
  }

  Future<void> _pick(BuildContext context) async {
    // Captured before the await: in the quick-add sheet this widget's context
    // belongs to a route that the picker sits on top of, and reaching for the
    // messenger afterwards is how the "created it" snackbar goes missing.
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showLocationPicker(
      context,
      repository: repository,
      title: 'Where is it?',
      rootLabel: 'Not filed anywhere',
      allowCreate: true,
      // A typed name lands inside whatever is selected now, so adding a shelf
      // to the cupboard you just picked is one more line of typing rather
      // than a trip to the Locations tab.
      createParentId: locationId.isEmpty ? null : locationId,
      now: now,
    );
    if (choice == null) return;
    onChanged(choice.id);
    final created = choice.location;
    if (!choice.created || created == null) return;
    final parentId = created.parentId;
    final where = parentId == null
        ? 'as a new room'
        : 'in ${repository.pathLabel(parentId)}';
    messenger.showSnackBar(
      SnackBar(content: Text('Created "${created.name}" $where')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filed = locationId.isNotEmpty || fallbackLabel.isNotEmpty;
    return InkWell(
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _value,
          style: filed
              ? theme.textTheme.bodyLarge
              : theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
