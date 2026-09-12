import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/derived_ids.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';

import '../support/builders.dart';

class _Mem implements LogPersistence {
  _Mem([this._text]);

  String? _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}

Hlc hlc(int ms) => Hlc(wallTimeMs: ms, counter: 0, nodeId: 'n');

/// A raw location record, for seeding shapes the API refuses to create.
Record _locationRecord(String id, String name, String? parentId) => Record(
  id: id,
  fields: {
    kTypeField: (kTypeLocation, hlc(1)),
    'name': (name, hlc(1)),
    'parent_id': (parentId, hlc(1)),
  },
);

void main() {
  final now = DateTime.utc(2026, 8, 5);
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  group('location records and items stay separate', () {
    test('a place never shows up in the items list', () async {
      await repo.createLocation(name: 'Korytarz', now: now);
      await repo.upsert(itemFixture(id: 'i1', name: 'Screwdriver'));

      expect(repo.listItems().map((i) => i.name), ['Screwdriver']);
      expect(repo.summary().total, 1);
    });

    test('an item is not readable as a place', () async {
      await repo.upsert(itemFixture(id: 'i1'));

      expect(repo.location('i1'), isNull);
    });

    test('a deleted place is not readable', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);

      await repo.deleteLocation(room.id);

      expect(repo.location(room.id), isNull);
      expect(repo.listLocations(), isEmpty);
    });
  });
  group('locationLabelFor', () {
    test('resolves a filed item through the tree', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );
      await repo.upsert(itemFixture(id: 'i1', locationId: shelf.id));

      expect(repo.locationLabelFor(repo.item('i1')!), 'Korytarz › Szafka');
    });

    // An item pulled mid-sync from a device still on the old build carries the
    // strings and no id, and would otherwise read as "nowhere" until the next
    // app start folded it in.
    test('falls back to the legacy strings for an unmigrated item', () {
      final legacy = itemFixture(room: 'Kuchnia', container: 'Szuflada');

      expect(repo.locationLabelFor(legacy), 'Kuchnia › Szuflada');
    });
  });
  group('runLocationMigration', () {
    test('folds legacy strings on open', () async {
      final store = _Mem();
      final old = await ItemRepository.openWith(
        persistence: store,
        nodeId: 'old',
        now: now,
      );
      await old.upsert(
        itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka'),
      );
      await old.close();

      final migrated = await ItemRepository.openWith(
        persistence: store,
        nodeId: 'new',
        now: now,
      );
      addTearDown(migrated.close);

      expect(
        migrated.pathLabel(migrated.item('i1')!.locationId),
        'Korytarz › Szafka',
      );
    });

    test(
      'keeps the legacy strings so an older build still reads them',
      () async {
        final store = _Mem();
        final old = await ItemRepository.openWith(
          persistence: store,
          nodeId: 'old',
          now: now,
        );
        await old.upsert(itemFixture(id: 'i1', room: 'Korytarz'));
        await old.close();

        final migrated = await ItemRepository.openWith(
          persistence: store,
          nodeId: 'new',
          now: now,
        );
        addTearDown(migrated.close);

        expect(migrated.item('i1')!.room, 'Korytarz');
      },
    );

    test('running it again changes nothing', () async {
      await repo.upsert(itemFixture(id: 'i1', room: 'Korytarz'));
      await repo.runLocationMigration(now: now);
      final after = repo.listLocations().length;

      await repo.runLocationMigration(now: now);

      expect(repo.listLocations().length, after);
    });

    test('is a no-op when there is nothing to fold', () async {
      await repo.upsert(itemFixture(id: 'i1'));

      await repo.runLocationMigration(now: now);

      expect(repo.listLocations(), isEmpty);
    });

    // Two devices folding the same legacy log must converge, or the first sync
    // leaves the user with two of every room.
    test('two devices folding the same log merge to one tree', () async {
      final store = _Mem();
      final old = await ItemRepository.openWith(
        persistence: store,
        nodeId: 'old',
        now: now,
      );
      await old.upsert(
        itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka'),
      );
      await old.upsert(itemFixture(id: 'i2', room: 'Kuchnia'));
      await old.close();
      final payload = store._text!;

      final a = await ItemRepository.openWith(
        persistence: _Mem(payload),
        nodeId: 'deviceA',
        now: now,
      );
      addTearDown(a.close);
      final b = await ItemRepository.openWith(
        persistence: _Mem(payload),
        nodeId: 'deviceB',
        // A different clock, as two real devices would have.
        now: now.add(const Duration(hours: 3)),
      );
      addTearDown(b.close);

      expect(a.listLocations().length, 3);
      expect(
        a.listLocations().map((l) => l.id).toSet(),
        b.listLocations().map((l) => l.id).toSet(),
      );

      final merged = await ItemRepository.openWith(
        persistence: _Mem(logToJson(mergeLogs(a.exportLog(), b.exportLog()))),
        nodeId: 'merged',
        now: now,
      );
      addTearDown(merged.close);

      expect(
        merged.listLocations().length,
        3,
        reason: 'two independent migrations must not double every room',
      );
      expect(
        merged.pathLabel(merged.item('i1')!.locationId),
        'Korytarz › Szafka',
      );
    });
  });
}
