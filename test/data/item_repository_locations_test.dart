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

Hlc _hlc(int ms) => Hlc(wallTimeMs: ms, counter: 0, nodeId: 'n');

/// A raw location record, for seeding shapes the API refuses to create.
Record _locationRecord(String id, String name, String? parentId) => Record(
  id: id,
  fields: {
    kTypeField: (kTypeLocation, _hlc(1)),
    'name': (name, _hlc(1)),
    'parent_id': (parentId, _hlc(1)),
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

  group('locationTree', () {
    test('nests to arbitrary depth', () async {
      final l1 = await repo.createLocation(name: 'korytarz', now: now);
      final l2 = await repo.createLocation(
        name: 'szafka z lewej',
        parentId: l1.id,
        now: now,
      );
      final l3 = await repo.createLocation(
        name: 'najwyższa półka',
        parentId: l2.id,
        now: now,
      );
      final l4 = await repo.createLocation(
        name: 'sekcja przy drzwiach',
        parentId: l3.id,
        now: now,
      );

      expect(
        repo.pathLabel(l4.id),
        'korytarz › szafka z lewej › najwyższa półka › sekcja przy drzwiach',
      );
      expect(repo.pathOf(l4.id).length, 4);

      var node = repo.locationTree().single;
      for (var depth = 0; depth < 3; depth++) {
        expect(node.depth, depth);
        node = node.children.single;
      }
      expect(node.depth, 3);
    });

    test('counts items directly and through the subtree', () async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final shelf = await repo.createLocation(
        name: 'Szafka',
        parentId: room.id,
        now: now,
      );
      await repo.upsert(itemFixture(id: 'i1', locationId: room.id));
      await repo.upsert(itemFixture(id: 'i2', locationId: shelf.id));
      await repo.upsert(itemFixture(id: 'i3', locationId: shelf.id));

      final node = repo.locationTree().single;

      expect(node.directItemCount, 1);
      // A cupboard reading "1 item" because everything is on its shelves is a
      // lie the user has to expand to disprove.
      expect(node.totalItemCount, 3);
      expect(node.children.single.directItemCount, 2);
    });

    test('ignores items pointing at a place that does not exist', () async {
      await repo.upsert(itemFixture(id: 'i1', locationId: 'ghost'));
      await repo.createLocation(name: 'Korytarz', now: now);

      expect(repo.locationTree().single.totalItemCount, 0);
    });

    test('orders siblings by sort key then name', () async {
      await repo.createLocation(name: 'Zebra', now: now);
      await repo.createLocation(name: 'Alpha', now: now);
      await repo.createLocation(name: 'Middle', sortKey: -1, now: now);

      expect(
        repo.locationTree().map((n) => n.name),
        ['Middle', 'Alpha', 'Zebra'],
      );
    });

    // A cycle is not hypothetical under CRDT merge: this device moves A under
    // B while another moves B under A, each write wins its own field, and the
    // merged graph loops. A naive walk would hang the app.
    test('a merged-in cycle terminates and is re-rooted', () async {
      final cyclic = await ItemRepository.openWith(
        persistence: _Mem(
          logToJson({
            'a': _locationRecord('a', 'Alpha', 'b'),
            'b': _locationRecord('b', 'Beta', 'a'),
            'c': _locationRecord('c', 'Gamma', null),
          }),
        ),
        nodeId: 'n',
        now: now,
      );
      addTearDown(cyclic.close);

      final tree = cyclic.locationTree();

      // Nothing vanished, and the walk returned at all.
      expect(
        tree.expand((n) => [n.name, ...n.children.map((c) => c.name)]).toSet(),
        {'Alpha', 'Beta', 'Gamma'},
      );
      expect(cyclic.pathOf('a').length, lessThanOrEqualTo(2));
      expect(cyclic.subtreeIds('a'), {'a', 'b'});
    });

    test('a place whose parent is missing is shown at the top', () async {
      final orphaned = await ItemRepository.openWith(
        persistence: _Mem(
          logToJson({'a': _locationRecord('a', 'Alpha', 'gone')}),
        ),
        nodeId: 'n',
        now: now,
      );
      addTearDown(orphaned.close);

      expect(orphaned.locationTree().map((n) => n.name), ['Alpha']);
    });

    test('watchLocationTree re-emits after a place is added', () async {
      final seen = <int>[];
      final sub = repo.watchLocationTree().listen((t) => seen.add(t.length));
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await repo.createLocation(name: 'Korytarz', now: now);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [0, 1]);
    });

    test('watchLocations re-emits after a place is added', () async {
      final seen = <int>[];
      final sub = repo.watchLocations().listen((l) => seen.add(l.length));
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await repo.createLocation(name: 'Korytarz', now: now);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [0, 1]);
    });
  });

  // Every one of these takes an injectable clock so tests need not depend on
  // wall time; the default branch still has to work, since that is what the
  // app itself uses.
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

      expect(
        repo.locationLabelFor(repo.item('i1')!),
        'Korytarz › Szafka',
      );
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
