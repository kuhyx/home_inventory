import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/barcode_link.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';

import '../support/builders.dart';
import '../support/seeded_persistence.dart';

void main() {
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  group('sync seam', () {
    test('exportLog exposes the raw records', () async {
      await repo.upsert(itemFixture());

      expect(repo.exportLog().containsKey('i1'), isTrue);
    });

    test('importLog merges rather than replaces', () async {
      await repo.upsert(itemFixture(id: 'mine'));

      await repo.importLog({
        'theirs': Record(
          id: 'theirs',
          fields: {kTypeField: (kTypeItem, hlc(1)), 'name': ('Theirs', hlc(1))},
        ),
      });

      expect(repo.listItems().map((i) => i.id).toSet(), {'mine', 'theirs'});
    });

    test('replaceAll swaps the whole log', () async {
      await repo.upsert(itemFixture(id: 'mine'));

      await repo.replaceAll({});

      expect(repo.listItems(), isEmpty);
    });

    test('pruneHistory drops ancient adjustments on demand', () async {
      final now = DateTime.utc(2026, 7, 26);
      await repo.replaceAll({
        'old': Record(
          id: 'old',
          fields: {
            kTypeField: (kTypeAdjustment, hlc(1)),
            'item_id': ('i1', hlc(1)),
            kAtField: (
              now.subtract(const Duration(days: 400)).toIso8601String(),
              hlc(1),
            ),
          },
        ),
      });

      await repo.pruneHistory(now: now);

      expect(repo.exportLog(), isEmpty);
    });

    test('pruneHistory is a no-op when nothing is ancient', () async {
      // The adjustment's timestamp comes from the item's updatedAt, so this
      // has to be inside the horizon or the test proves the opposite thing.
      await repo.upsert(itemFixture(updatedAt: DateTime.utc(2026, 7, 20)));
      final before = repo.exportLog().length;

      await repo.pruneHistory(now: DateTime.utc(2026, 7, 26));

      expect(before, 2);
      expect(repo.exportLog(), hasLength(before));
    });
  });
  group('backup file', () {
    test('a round trip through JSON preserves the inventory', () async {
      await repo.upsert(
        itemFixture(id: 'a', name: 'Cable', quantity: 4, room: 'Office'),
      );
      final json = repo.exportJson();

      final other = await ItemRepository.openInMemory();
      addTearDown(other.close);
      await other.importJson(json);

      final restored = other.item('a')!;
      expect(restored.name, 'Cable');
      expect(restored.quantity, 4);
      expect(restored.room, 'Office');
    });

    test('the quantity history survives the round trip', () async {
      await repo.upsert(itemFixture(id: 'a', quantity: 4));
      await repo.adjustQuantity('a', -1, AdjustmentSource.use);
      final json = repo.exportJson();

      final other = await ItemRepository.openInMemory();
      addTearDown(other.close);
      await other.importJson(json);

      expect(other.historyFor('a'), hasLength(2));
    });

    // Restoring a month-old backup must not undo this month's edits: import
    // is a CRDT merge, and the per-field clocks decide each winner.
    test('importing merges rather than replaces', () async {
      await repo.upsert(itemFixture(id: 'old', name: 'Archived'));
      final backup = repo.exportJson();

      final other = await ItemRepository.openInMemory();
      addTearDown(other.close);
      await other.upsert(itemFixture(id: 'new', name: 'Recent'));
      await other.importJson(backup);

      expect(other.item('old')!.name, 'Archived');
      expect(other.item('new')!.name, 'Recent');
    });

    test('a newer local edit outranks the backup', () async {
      await repo.upsert(
        itemFixture(
          id: 'a',
          name: 'Old name',
          updatedAt: DateTime.utc(2026, 3),
        ),
      );
      final backup = repo.exportJson();
      await repo.upsert(
        itemFixture(
          id: 'a',
          name: 'New name',
          updatedAt: DateTime.utc(2026, 6),
        ),
      );

      await repo.importJson(backup);

      expect(repo.item('a')!.name, 'New name');
    });

    test('text that is not JSON is rejected', () {
      expect(() => repo.importJson('not json'), throwsFormatException);
    });

    test('JSON of the wrong shape is rejected', () {
      expect(() => repo.importJson('[1, 2, 3]'), throwsA(isA<TypeError>()));
    });
  });

  // A restored copy must lose to genuinely newer data on another device, so
  // its clocks come from the item's own edit time rather than "now".
  test('recordAtItemTime stamps clocks from the item edit time', () {
    final item = itemFixture(updatedAt: DateTime.utc(2020, 3, 4));

    final record = ItemRepository.recordAtItemTime(item, 'node-a');

    expect(record.id, 'i1');
    expect(
      record.fields['name']!.$2.wallTimeMs,
      DateTime.utc(2020, 3, 4).millisecondsSinceEpoch,
    );
    expect(record.fields[kTypeField]!.$1, kTypeItem);
  });
}
