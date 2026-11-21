/// The name dialog for adding or renaming a place.
library;

import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/ui/field_error.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a place name; resolves to the trimmed name, or null on cancel.
///
/// [glyph] and [spoken] title the dialog (icon + screen-reader label).
/// [parentId] is where the place lives, so the dialog can refuse a name a
/// sibling already uses; [ignoringId] skips the place being renamed.
Future<String?> showPlaceNameDialog(
  BuildContext context, {
  required ItemRepository repository,
  required IconData glyph,
  required String spoken,
  required String? parentId,
  String? initial,
  String? ignoringId,
}) {
  final controller = TextEditingController(text: initial ?? '');
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Icon(glyph, semanticLabel: spoken),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.edit, semanticLabel: 'Name'),
          ),
          validator: (value) {
            final name = (value ?? '').trim();
            if (name.isEmpty) return invalidField;
            // Sibling names must stay unique: ids are derived from
            // (parent, folded name), so two "Shelf" rows under one cupboard
            // would collapse onto a single record.
            if (repository.hasChildNamed(
              parentId,
              name,
              ignoringId: ignoringId,
            )) {
              return invalidField;
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          key: const Key('dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, semanticLabel: 'Cancel'),
        ),
        FilledButton(
          key: const Key('dialog_save'),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: const Icon(Icons.save, semanticLabel: 'Save'),
        ),
      ],
    ),
  );
}
