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

  group('renameLocation', () {
    test('changes the name but never the id', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);

      await repo.renameLocation(room.id, 'Hall', now: now);

      expect(repo.location(room.id)?.name, 'Hall');
      expect(repo.listLocations().length, 1);
    });

    test('items filed there follow the rename', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      await repo.upsert(itemFixture(id: 'i1', locationId: room.id));

      await repo.renameLocation(room.id, 'Hall', now: now);

      expect(repo.pathLabel(repo.item('i1')!.locationId), 'Hall');
    });

    test('an unknown id is a no-op', () async {
      await repo.renameLocation('nope', 'Hall', now: now);

      expect(repo.listLocations(), isEmpty);
    });

    // Writing the whole record would re-stamp every field with a fresh clock,
    // so this device's stale copy of parent_id would outrank a move made on
    // another device. Renaming has to touch the name alone.
    test('leaves the parent clock untouched', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );

      await repo.renameLocation(shelf.id, 'Inna', now: now);

      expect(repo.location(shelf.id)?.parentId, room.id);
    });
  });
  group('moveLocation', () {
    test('re-parents a place', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', now: now);

      final moved = await repo.moveLocation(b.id, a.id, now: now);

      expect(moved, isTrue);
      expect(repo.pathLabel(b.id), 'A › B');
    });

    test('moves a place back to the top level', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', parentId: a.id, now: now);

      await repo.moveLocation(b.id, null, now: now);

      expect(repo.location(b.id)?.parentId, isNull);
      expect(repo.pathLabel(b.id), 'B');
    });

    test('refuses a move into its own subtree', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', parentId: a.id, now: now);

      final moved = await repo.moveLocation(a.id, b.id, now: now);

      expect(moved, isFalse);
      expect(repo.location(a.id)?.parentId, isNull);
    });

    test('refuses a move into itself', () async {
      final a = await repo.createLocation(name: 'A', now: now);

      expect(await repo.moveLocation(a.id, a.id, now: now), isFalse);
    });

    test('an unknown id is refused', () async {
      expect(await repo.moveLocation('nope', null, now: now), isFalse);
    });
  });
  group('deleteLocation', () {
    // A sticky CRDT delete plus a cascade means one mis-tap removes a whole
    // branch on every device, with no undo. Children resurface instead.
    test('does not cascade; children move up to the top level', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );

      await repo.deleteLocation(room.id);

      expect(repo.location(shelf.id), isNotNull);
      expect(repo.locationTree().map((n) => n.name), ['Szafka']);
      expect(repo.locationTree().single.depth, 0);
    });

    test('items filed in a deleted place read as unfiled', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      await repo.upsert(itemFixture(id: 'i1', locationId: room.id));

      await repo.deleteLocation(room.id);

      // The id is still on the item, but it resolves to nothing rather than
      // to a stale name.
      expect(repo.pathLabel(repo.item('i1')!.locationId), '');
      expect(repo.locationLabelFor(repo.item('i1')!), '');
    });
  });
}
