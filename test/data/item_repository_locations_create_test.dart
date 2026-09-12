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

  group('createLocation', () {
    test('creates a top-level place', () async {
      final created = await repo.createLocation(name: 'Korytarz', now: now);

      expect(created.name, 'Korytarz');
      expect(created.parentId, isNull);
      expect(repo.location(created.id)?.name, 'Korytarz');
    });

    test('creates a nested place', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);

      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );

      expect(shelf.parentId, room.id);
      expect(repo.pathLabel(shelf.id), 'Korytarz › Szafka');
    });

    // A room that exists before anything is in it is the entire reason
    // locations became records instead of strings on an item.
    test('a place with no items still exists and shows in the tree', () async {
      await repo.createLocation(name: 'Garaż', now: now);

      expect(repo.locationTree().map((n) => n.name), ['Garaż']);
      expect(repo.locationTree().single.totalItemCount, 0);
    });

    test('creating the same place twice yields one record', () async {
      final first = await repo.createLocation(name: 'Korytarz', now: now);
      final second = await repo.createLocation(name: 'korytarz  ', now: now);

      expect(second.id, first.id);
      expect(repo.listLocations().length, 1);
    });

    test('trims the stored name', () async {
      final created = await repo.createLocation(name: '  Korytarz  ', now: now);

      expect(created.name, 'Korytarz');
    });

    test(
      'the same name under different parents are different places',
      () async {
        final a = await repo.createLocation(name: 'A', now: now);
        final b = await repo.createLocation(name: 'B', now: now);

        final shelfA = await repo.createLocation(
          name: 'Półka',
          parentId: a.id,
          now: now,
        );
        final shelfB = await repo.createLocation(
          name: 'Półka',
          parentId: b.id,
          now: now,
        );

        expect(shelfA.id, isNot(shelfB.id));
      },
    );
  });
  group('hasChildNamed', () {
    test('spots a sibling collision, folding case', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      await repo.createLocation(name: 'Szafka', parentId: room.id, now: now);

      expect(repo.hasChildNamed(room.id, 'szafka'), isTrue);
      expect(repo.hasChildNamed(room.id, 'Inna'), isFalse);
      expect(repo.hasChildNamed(null, 'Szafka'), isFalse);
    });

    test('ignores the place being renamed', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);

      expect(
        repo.hasChildNamed(null, 'Korytarz', ignoringId: room.id),
        isFalse,
        reason: 'renaming a place to its own name is not a collision',
      );
    });
  });
  group('the default clock', () {
    test(
      'createLocation, renameLocation and moveLocation all fall back',
      () async {
        final room = await repo.createLocation(name: 'Korytarz');
        final shelf = await repo.createLocation(
          name: 'Szafka',
          parentId: room.id,
        );

        await repo.renameLocation(shelf.id, 'Inna');
        final moved = await repo.moveLocation(shelf.id, null);

        expect(moved, isTrue);
        expect(repo.location(shelf.id)?.name, 'Inna');
        expect(repo.location(shelf.id)?.parentId, isNull);
      },
    );

    test('runLocationMigration falls back', () async {
      await repo.upsert(itemFixture(id: 'i1', room: 'Korytarz'));

      await repo.runLocationMigration();

      expect(repo.listLocations().single.name, 'Korytarz');
    });
  });
}
