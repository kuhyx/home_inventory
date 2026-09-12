// The `--set` / `--delete` edit vocabulary for tool/sync_smoke.dart.
//
// Split out to keep each file readable in one piece; see DOCS-sync-smoke.md
// for what the flags mean.

import 'dart:io';

import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/item.dart';

Future<void> applyEdits(List<String> args, ItemRepository repository) async {
  final seed = argValue(args, '--seed');
  if (seed != null) {
    final at = DateTime.now();
    await repository.upsert(
      Item(
        id: 'smoke-${at.millisecondsSinceEpoch}',
        name: seed,
        quantity: 3,
        unit: '',
        locationId: '',
        room: 'Smoke test',
        container: 'Throwaway',
        category: '',
        lowStockAt: null,
        bestBefore: null,
        wanted: false,
        sellable: false,
        notes: 'written by tool/sync_smoke.dart',
        createdAt: at,
        updatedAt: at,
      ),
    );
    stdout.writeln('Seeded "$seed".');
  }

  final delete = argValue(args, '--delete');
  if (delete != null) {
    await repository.delete(delete);
    stdout.writeln('Deleted $delete.');
  }

  final setIndex = args.indexOf('--set');
  if (setIndex == -1) return;
  if (setIndex + 3 >= args.length) {
    stderr.writeln('--set needs <id> <field> <value>.');
    exitCode = 2;
    return;
  }
  final id = args[setIndex + 1];
  final field = args[setIndex + 2];
  final value = args[setIndex + 3];
  final current = repository.item(id);
  if (current == null) {
    stderr.writeln('No item $id here. Sync first, or check --list output.');
    exitCode = 2;
    return;
  }
  await _setField(repository, current, field, value);
}

Future<void> _setField(
  ItemRepository repository,
  Item current,
  String field,
  String value,
) async {
  // Quantity goes through adjustQuantity rather than upsert so the change is
  // attributed explicitly. A silent default here is how a recount gets
  // recorded as consumption and quadruples the burn rate.
  if (field == 'quantity') {
    final wanted = double.tryParse(value);
    if (wanted == null) {
      stderr.writeln('quantity must be a number.');
      exitCode = 2;
      return;
    }
    await repository.setQuantity(
      current.id,
      wanted,
      AdjustmentSource.correction,
    );
    stdout.writeln('Set quantity of ${current.name} to $value.');
    return;
  }

  final updated = switch (field) {
    'name' => current.copyWith(name: value, updatedAt: DateTime.now()),
    'room' => current.copyWith(room: value, updatedAt: DateTime.now()),
    'container' => current.copyWith(
      container: value,
      updatedAt: DateTime.now(),
    ),
    'notes' => current.copyWith(notes: value, updatedAt: DateTime.now()),
    _ => null,
  };
  if (updated == null) {
    stderr.writeln(
      'Unknown field "$field" — try name, room, container, notes or quantity.',
    );
    exitCode = 2;
    return;
  }
  await repository.upsert(updated);
  stdout.writeln('Set $field of ${current.name} to "$value".');
}

/// The value following `name` on the command line, or null.
String? argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
