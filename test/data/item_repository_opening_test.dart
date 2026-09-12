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

  group('opening', () {
    test('starts empty and exposes its node id', () {
      expect(repo.listItems(), isEmpty);
      expect(repo.nodeId, 'test-node');
    });

    test('prunes ancient adjustments before anything can push them', () async {
      final now = DateTime.utc(2026, 7, 26);
      final ancient = now.subtract(const Duration(days: 400));
      final seeded = SeededPersistence(
        logToJson({
          'keep': Record(id: 'keep', fields: {kTypeField: (kTypeItem, hlc(1))}),
          'drop': Record(
            id: 'drop',
            fields: {
              kTypeField: (kTypeAdjustment, hlc(1)),
              kAtField: (ancient.toIso8601String(), hlc(1)),
            },
          ),
        }),
      );

      final loaded = await ItemRepository.openWith(
        persistence: seeded,
        nodeId: 'n',
        now: now,
      );
      addTearDown(loaded.close);

      expect(loaded.exportLog().keys, ['keep']);
      // Persisted, not just filtered in memory.
      expect(seeded.text, isNot(contains('drop')));
    });

    // The phantom-item bug this allowlist exists to prevent: a record kind
    // written by a newer build must not render as an item on an older one,
    // while still being kept in the log so syncing back does not destroy it.
    test('a record kind from a newer build is kept but never listed', () async {
      final seeded = SeededPersistence(
        logToJson({
          'real': Record(
            id: 'real',
            fields: {
              kTypeField: (kTypeItem, hlc(1)),
              'name': ('Screwdriver', hlc(1)),
            },
          ),
          'korytarz': Record(
            id: 'korytarz',
            fields: {
              kTypeField: (kTypeLocation, hlc(1)),
              'name': ('Korytarz', hlc(1)),
            },
          ),
          'future': Record(
            id: 'future',
            fields: {kTypeField: ('quantum-widget', hlc(1))},
          ),
        }),
      );

      final loaded = await ItemRepository.openWith(
        persistence: seeded,
        nodeId: 'n',
        now: DateTime.utc(2026, 7, 26),
      );
      addTearDown(loaded.close);

      expect(loaded.listItems().map((i) => i.id), ['real']);
      expect(loaded.item('korytarz'), isNull);
      expect(loaded.item('future'), isNull);
      // Kept, so a round-trip through this build does not drop them.
      expect(loaded.exportLog().keys.toSet(), {'real', 'korytarz', 'future'});
    });

    test('leaves storage untouched when nothing is ancient', () async {
      final seeded = SeededPersistence(
        logToJson({
          'keep': Record(id: 'keep', fields: {kTypeField: (kTypeItem, hlc(1))}),
        }),
      );
      final before = seeded.text;

      final loaded = await ItemRepository.openWith(
        persistence: seeded,
        nodeId: 'n',
        now: DateTime.utc(2026, 7, 26),
      );
      addTearDown(loaded.close);

      expect(seeded.text, before);
    });
  });
  group('defensive record reading', () {
    // A double whose value is integral serialises to JSON as `1` and comes
    // back as `int`; a plain `as double` cast would throw under strict-casts
    // on the second run of the app. This is the crash this guards.
    test('reads an integral quantity stored as a JSON int', () async {
      await repo.replaceAll({
        'i1': Record(
          id: 'i1',
          fields: {
            kTypeField: (kTypeItem, hlc(1)),
            'quantity': (3, hlc(1)),
            'low_stock_at': (1, hlc(1)),
          },
        ),
      });

      final item = repo.item('i1')!;
      expect(item.quantity, 3.0);
      expect(item.lowStockAt, 1.0);
    });

    test('falls back for missing, null and wrongly-typed fields', () async {
      await repo.replaceAll({
        'i1': Record(
          id: 'i1',
          fields: {
            kTypeField: (kTypeItem, hlc(1)),
            'name': (42, hlc(1)),
            'low_stock_at': (null, hlc(1)),
            'created_at': (99, hlc(1)),
            'updated_at': ('not-a-date', hlc(1)),
          },
        ),
      });

      final item = repo.item('i1')!;
      expect(item.name, '');
      expect(item.quantity, 0);
      expect(item.lowStockAt, isNull);
      expect(item.wanted, isFalse);
      expect(item.sellable, isFalse);
      expect(item.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(item.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('skips adjustment records missing an item id or timestamp', () async {
      await repo.replaceAll({
        'noItem': Record(
          id: 'noItem',
          fields: {
            kTypeField: (kTypeAdjustment, hlc(1)),
            kAtField: (DateTime.utc(2026).toIso8601String(), hlc(1)),
          },
        ),
        'noAt': Record(
          id: 'noAt',
          fields: {
            kTypeField: (kTypeAdjustment, hlc(1)),
            'item_id': ('i1', hlc(1)),
          },
        ),
        'badAt': Record(
          id: 'badAt',
          fields: {
            kTypeField: (kTypeAdjustment, hlc(1)),
            'item_id': ('i1', hlc(1)),
            kAtField: ('nope', hlc(1)),
          },
        ),
      });

      expect(repo.historyFor('i1'), isEmpty);
    });

    test('ignores tombstoned adjustments when building history', () async {
      await repo.upsert(itemFixture(quantity: 2));
      final adjustmentId = repo.historyFor('i1').single.id;

      await repo.delete(adjustmentId);

      expect(repo.historyFor('i1'), isEmpty);
    });
  });
}
