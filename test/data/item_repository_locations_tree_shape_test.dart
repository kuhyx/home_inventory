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

      expect(repo.locationTree().map((n) => n.name), [
        'Middle',
        'Alpha',
        'Zebra',
      ]);
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
}
