/// Restocking by barcode, from anywhere that can show a snack bar.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/ui/code_prompt.dart';

/// Asks for a code and restocks whatever it is linked to.
///
/// Unpacking the shopping is the moment this exists for: one code per bag, no
/// navigating to each item first. An unknown code says so rather than silently
/// doing nothing — the alternative is a user tapping the same button three
/// times wondering which part is broken.
Future<void> promptScanRestock(
  BuildContext context, {
  required ItemRepository repository,
  DateTime Function()? now,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final entry = await promptForCode(context, title: 'Scan to restock');
  if (entry == null) return;
  final item = await repository.applyScan(
    entry.code,
    source: AdjustmentSource.restock,
    now: now?.call(),
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        item == null
            ? 'No item is linked to ${entry.code}'
            : 'Restocked ${item.name}',
      ),
    ),
  );
}
