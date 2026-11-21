/// The text controllers behind the full item form, seeded from an item.
library;

import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/best_before_field.dart';
import 'package:material_ui/material_ui.dart';

/// One controller per free-text field of the item form.
///
/// A null item seeds an empty form with a quantity of 1. Owned by the form's
/// state, which calls [dispose] once.
class ItemFormControllers {
  /// Seeds every field from [item], or the defaults when it is null.
  ItemFormControllers(Item? item)
    : name = TextEditingController(text: item?.name ?? ''),
      quantity = TextEditingController(
        text: item == null ? '1' : formatQuantity(item.quantity),
      ),
      unit = TextEditingController(text: item?.unit ?? ''),
      category = TextEditingController(text: item?.category ?? ''),
      lowStockAt = TextEditingController(
        text: item?.lowStockAt == null ? '' : formatQuantity(item!.lowStockAt!),
      ),
      bestBefore = TextEditingController(text: formatIsoDate(item?.bestBefore)),
      notes = TextEditingController(text: item?.notes ?? '');

  /// Item name.
  final TextEditingController name;

  /// Quantity on hand.
  final TextEditingController quantity;

  /// Unit, blank for a plain count.
  final TextEditingController unit;

  /// Category.
  final TextEditingController category;

  /// Low-stock threshold, blank for never.
  final TextEditingController lowStockAt;

  /// Best-before date as yyyy-mm-dd.
  final TextEditingController bestBefore;

  /// Free-form notes.
  final TextEditingController notes;

  /// Disposes every controller.
  void dispose() {
    for (final controller in [
      name,
      quantity,
      unit,
      category,
      lowStockAt,
      bestBefore,
      notes,
    ]) {
      controller.dispose();
    }
  }
}
