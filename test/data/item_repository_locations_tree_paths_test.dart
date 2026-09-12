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

  group('paths and subtrees', () {
    test('pathOf is empty for an unknown id', () {
      expect(repo.pathOf('nope'), isEmpty);
      expect(repo.pathLabel('nope'), '');
    });

    test('subtreeIds includes the place itself', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);

      expect(repo.subtreeIds(room.id), {room.id});
    });

    test('subtreeIds reaches every descendant', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', parentId: a.id, now: now);
      final c = await repo.createLocation(name: 'C', parentId: b.id, now: now);
      await repo.createLocation(name: 'Elsewhere', now: now);

      expect(repo.subtreeIds(a.id), {a.id, b.id, c.id});
    });

    test('itemCountAt counts only what is filed exactly there', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );
      await repo.upsert(itemFixture(id: 'i1', locationId: room.id));
      await repo.upsert(itemFixture(id: 'i2', locationId: shelf.id));

      expect(repo.itemCountAt(room.id), 1);
      expect(repo.itemCountAt(shelf.id), 1);
    });
  });
  group('defaults for a new item', () {
    test('mostUsedLocationId is empty with nothing filed', () async {
      await repo.createLocation(name: 'Korytarz', now: now);
      await repo.upsert(itemFixture(id: 'i1'));

      expect(repo.mostUsedLocationId(), '');
    });

    test('mostUsedLocationId picks the busiest place', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );
      await repo.upsert(itemFixture(id: 'i1', locationId: shelf.id));
      await repo.upsert(itemFixture(id: 'i2', locationId: shelf.id));
      await repo.upsert(itemFixture(id: 'i3', locationId: room.id));

      expect(repo.mostUsedLocationId(), shelf.id);
    });

    // A tie has to resolve the same way every rebuild, or the quick-add
    // default flips between two shelves for no visible reason.
    test('mostUsedLocationId breaks a tie deterministically', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', now: now);
      await repo.upsert(itemFixture(id: 'i1', locationId: a.id));
      await repo.upsert(itemFixture(id: 'i2', locationId: b.id));

      final expected = [a.id, b.id]..sort();
      expect(repo.mostUsedLocationId(), expected.first);
      expect(repo.mostUsedLocationId(), expected.first);
    });

    test('mostUsedLocationId ignores a place that is gone', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      await repo.upsert(itemFixture(id: 'i1', locationId: room.id));
      await repo.deleteLocation(room.id);

      expect(repo.mostUsedLocationId(), '');
    });

    test('rootOfSelection returns the place a subtree was rooted at', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );
      await repo.createLocation(name: 'Półka', parentId: shelf.id, now: now);

      expect(repo.rootOfSelection(repo.subtreeIds(room.id)), room.id);
      expect(repo.rootOfSelection(repo.subtreeIds(shelf.id)), shelf.id);
    });

    test('rootOfSelection is empty for nothing, or for unknown ids', () {
      expect(repo.rootOfSelection(const {}), '');
      expect(repo.rootOfSelection(const {'nope'}), '');
    });

    test('rootOfSelection breaks a depth tie on id', () async {
      final a = await repo.createLocation(name: 'A', now: now);
      final b = await repo.createLocation(name: 'B', now: now);

      final expected = [a.id, b.id]..sort();
      expect(repo.rootOfSelection({a.id, b.id}), expected.first);
    });
  });
}
