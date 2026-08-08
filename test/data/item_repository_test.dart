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

/// A persistence double that also lets a test seed a pre-existing payload,
/// which is how the load-time pruning path gets exercised.
class SeededPersistence implements LogPersistence {
  SeededPersistence([this._text]);

  String? _text;

  /// What is currently stored.
  String? get text => _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}

Hlc _hlc(int ms) => Hlc(wallTimeMs: ms, counter: 0, nodeId: 'n');

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
          'keep': Record(
            id: 'keep',
            fields: {kTypeField: (kTypeItem, _hlc(1))},
          ),
          'drop': Record(
            id: 'drop',
            fields: {
              kTypeField: (kTypeAdjustment, _hlc(1)),
              kAtField: (ancient.toIso8601String(), _hlc(1)),
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
              kTypeField: (kTypeItem, _hlc(1)),
              'name': ('Screwdriver', _hlc(1)),
            },
          ),
          'korytarz': Record(
            id: 'korytarz',
            fields: {
              kTypeField: (kTypeLocation, _hlc(1)),
              'name': ('Korytarz', _hlc(1)),
            },
          ),
          'future': Record(
            id: 'future',
            fields: {kTypeField: ('quantum-widget', _hlc(1))},
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
          'keep': Record(
            id: 'keep',
            fields: {kTypeField: (kTypeItem, _hlc(1))},
          ),
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

  group('upsert and read', () {
    test('stores and reads back every field', () async {
      final item = itemFixture(
        name: 'Flour',
        quantity: 2.5,
        unit: 'kg',
        room: 'Kitchen',
        container: 'Pantry',
        category: 'Food',
        lowStockAt: 1,
        wanted: true,
        sellable: true,
        notes: 'wholemeal',
        createdAt: DateTime.utc(2026, 5),
        updatedAt: DateTime.utc(2026, 6),
      );

      await repo.upsert(item);

      final stored = repo.item('i1')!;
      expect(stored.name, 'Flour');
      expect(stored.quantity, 2.5);
      expect(stored.unit, 'kg');
      expect(stored.room, 'Kitchen');
      expect(stored.container, 'Pantry');
      expect(stored.category, 'Food');
      expect(stored.lowStockAt, 1);
      expect(stored.wanted, isTrue);
      expect(stored.sellable, isTrue);
      expect(stored.notes, 'wholemeal');
      expect(stored.createdAt, DateTime.utc(2026, 5));
      expect(stored.updatedAt, DateTime.utc(2026, 6));
    });

    test('a brand new item records its opening quantity as initial', () async {
      await repo.upsert(itemFixture(quantity: 4));

      final history = repo.historyFor('i1');
      expect(history, hasLength(1));
      expect(history.single.source, AdjustmentSource.initial);
      expect(history.single.delta, 4);
    });

    test('creating an item at zero records nothing', () async {
      await repo.upsert(itemFixture(quantity: 0));

      expect(repo.historyFor('i1'), isEmpty);
    });

    test('re-saving with an unchanged quantity records nothing', () async {
      await repo.upsert(itemFixture(quantity: 4));
      await repo.upsert(itemFixture(quantity: 4, name: 'Renamed'));

      expect(repo.item('i1')!.name, 'Renamed');
      expect(repo.historyFor('i1'), hasLength(1));
    });

    // The form is the only caller that reaches upsert with a changed
    // quantity, and a form edit is a recount — attributing it to `use` would
    // quietly inflate the consumption rate.
    test('a changed quantity via upsert is a correction by default', () async {
      await repo.upsert(itemFixture(quantity: 4));
      await repo.upsert(itemFixture(quantity: 1));

      expect(repo.historyFor('i1').last.source, AdjustmentSource.correction);
      expect(repo.historyFor('i1').last.delta, -3);
    });

    test('the source can be overridden explicitly', () async {
      await repo.upsert(itemFixture(quantity: 4));
      await repo.upsert(
        itemFixture(quantity: 6),
        source: AdjustmentSource.restock,
      );

      expect(repo.historyFor('i1').last.source, AdjustmentSource.restock);
    });

    test('item() returns null for an unknown id', () {
      expect(repo.item('nope'), isNull);
    });

    test('item() returns null for a deleted item', () async {
      await repo.upsert(itemFixture());

      await repo.delete('i1');

      expect(repo.item('i1'), isNull);
      expect(repo.listItems(), isEmpty);
    });

    // Adjustments share the log with items; asking for one by id must not
    // hand back a nonsense item.
    test('item() returns null for an adjustment record', () async {
      await repo.upsert(itemFixture(quantity: 2));
      final adjustmentId = repo.historyFor('i1').single.id;

      expect(repo.item(adjustmentId), isNull);
    });

    test('adjustments never appear in the item list', () async {
      await repo.upsert(itemFixture(quantity: 2));

      expect(repo.listItems(), hasLength(1));
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
            kTypeField: (kTypeItem, _hlc(1)),
            'quantity': (3, _hlc(1)),
            'low_stock_at': (1, _hlc(1)),
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
            kTypeField: (kTypeItem, _hlc(1)),
            'name': (42, _hlc(1)),
            'low_stock_at': (null, _hlc(1)),
            'created_at': (99, _hlc(1)),
            'updated_at': ('not-a-date', _hlc(1)),
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
            kTypeField: (kTypeAdjustment, _hlc(1)),
            kAtField: (DateTime.utc(2026).toIso8601String(), _hlc(1)),
          },
        ),
        'noAt': Record(
          id: 'noAt',
          fields: {
            kTypeField: (kTypeAdjustment, _hlc(1)),
            'item_id': ('i1', _hlc(1)),
          },
        ),
        'badAt': Record(
          id: 'badAt',
          fields: {
            kTypeField: (kTypeAdjustment, _hlc(1)),
            'item_id': ('i1', _hlc(1)),
            kAtField: ('nope', _hlc(1)),
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

  group('quantity writes', () {
    setUp(() async {
      await repo.upsert(
        itemFixture(quantity: 5, room: 'Kitchen', lowStockAt: 2),
      );
    });

    test('adjustQuantity applies the delta and records the source', () async {
      final updated = await repo.adjustQuantity(
        'i1',
        -2,
        AdjustmentSource.use,
        now: DateTime.utc(2026, 6),
      );

      expect(updated!.quantity, 3);
      expect(repo.item('i1')!.quantity, 3);
      expect(repo.historyFor('i1').last.source, AdjustmentSource.use);
      expect(repo.historyFor('i1').last.delta, -2);
    });

    test('adjustQuantity clamps at zero rather than going negative', () async {
      final updated = await repo.adjustQuantity(
        'i1',
        -99,
        AdjustmentSource.use,
      );

      expect(updated!.quantity, 0);
      expect(repo.historyFor('i1').last.delta, -5);
    });

    test('adjustQuantity is a no-op for a zero delta', () async {
      await repo.adjustQuantity('i1', 0, AdjustmentSource.use);

      expect(repo.historyFor('i1'), hasLength(1));
    });

    test('adjustQuantity returns null for an unknown item', () async {
      expect(
        await repo.adjustQuantity('nope', -1, AdjustmentSource.use),
        isNull,
      );
    });

    test('setQuantity writes an absolute value', () async {
      final updated = await repo.setQuantity(
        'i1',
        9,
        AdjustmentSource.restock,
      );

      expect(updated!.quantity, 9);
      expect(repo.historyFor('i1').last.delta, 4);
    });

    test('setQuantity clamps a negative to zero', () async {
      final updated = await repo.setQuantity(
        'i1',
        -4,
        AdjustmentSource.correction,
      );

      expect(updated!.quantity, 0);
    });

    test('setQuantity to the current value records nothing', () async {
      await repo.setQuantity('i1', 5, AdjustmentSource.correction);

      expect(repo.historyFor('i1'), hasLength(1));
    });

    test('setQuantity returns null for an unknown item', () async {
      expect(
        await repo.setQuantity('nope', 1, AdjustmentSource.use),
        isNull,
      );
    });

    // The reason for per-field LWW in the first place: a quantity write must
    // leave every other field's clock alone, so a concurrent edit to the
    // location on another device still wins on merge.
    test('a quantity write touches only quantity and updated_at', () async {
      final before = repo.exportLog()['i1']!;
      final roomClockBefore = before.fields['room']!.$2;

      await repo.adjustQuantity('i1', -1, AdjustmentSource.use);

      final after = repo.exportLog()['i1']!;
      expect(after.fields['room']!.$2, roomClockBefore);
      expect(after.fields['room']!.$1, 'Kitchen');
      expect(after.fields['quantity']!.$2, isNot(roomClockBefore));
    });
  });

  group('filtering and sorting', () {
    setUp(() async {
      await repo.upsert(
        itemFixture(
          id: 'a',
          name: 'Cable',
          quantity: 4,
          room: 'Office',
          container: 'Drawer',
          category: 'Cables',
          updatedAt: DateTime.utc(2026, 3),
          createdAt: DateTime.utc(2026),
        ),
      );
      await repo.upsert(
        itemFixture(
          id: 'b',
          name: 'apples',
          quantity: 1,
          lowStockAt: 2,
          room: 'Kitchen',
          container: 'Bowl',
          category: 'Food',
          updatedAt: DateTime.utc(2026, 5),
          createdAt: DateTime.utc(2026, 2),
        ),
      );
      await repo.upsert(
        itemFixture(
          id: 'c',
          name: 'Bleach',
          quantity: 0,
          room: 'Kitchen',
          container: 'Under sink',
          category: 'Cleaning',
          wanted: true,
          updatedAt: DateTime.utc(2026, 4),
          createdAt: DateTime.utc(2026, 3),
        ),
      );
    });

    test('defaults to newest-edited first', () {
      expect(repo.listItems().map((i) => i.id), ['b', 'c', 'a']);
    });

    test('sorts by name, case-insensitively', () {
      expect(
        repo.listItems(sort: ItemSort.nameAsc).map((i) => i.id),
        ['b', 'c', 'a'],
      );
    });

    test('sorts by creation date', () {
      expect(
        repo.listItems(sort: ItemSort.createdDesc).map((i) => i.id),
        ['c', 'b', 'a'],
      );
    });

    test('sorts scarcest first', () {
      expect(
        repo.listItems(sort: ItemSort.quantityAsc).map((i) => i.id),
        ['c', 'b', 'a'],
      );
    });

    test('sorts by location, then name', () {
      expect(
        repo.listItems(sort: ItemSort.locationAsc).map((i) => i.id),
        ['b', 'c', 'a'],
      );
    });

    test('sorts out, then low, then fine', () {
      expect(
        repo.listItems(sort: ItemSort.lowStockFirst).map((i) => i.id),
        ['c', 'b', 'a'],
      );
    });

    test('breaks a quantity tie by name', () async {
      await repo.upsert(itemFixture(id: 'd', name: 'Aardvark', quantity: 4));

      expect(
        repo
            .listItems(sort: ItemSort.quantityAsc)
            .map((i) => i.id)
            .toList()
            .sublist(2),
        ['d', 'a'],
      );
    });

    test('breaks a location tie by container then name', () async {
      await repo.upsert(
        itemFixture(
          id: 'e',
          name: 'Almonds',
          room: 'Kitchen',
          container: 'Bowl',
        ),
      );

      expect(
        repo.listItems(sort: ItemSort.locationAsc).map((i) => i.id).first,
        'e',
      );
    });

    test('breaks a stock-state tie by quantity then name', () async {
      await repo.upsert(
        itemFixture(id: 'f', name: 'Aspirin', quantity: 0),
      );

      expect(
        repo.listItems(sort: ItemSort.lowStockFirst).map((i) => i.id).take(2),
        ['f', 'c'],
      );
    });

    test('applies the filter', () async {
      // Fold the seeded legacy strings into places first, then filter by the
      // resulting id — the path the real app takes.
      await repo.runLocationMigration(now: DateTime.utc(2026, 8, 5));
      final kitchen = repo.listLocations().firstWhere(
        (l) => l.name == 'Kitchen',
      );

      expect(
        repo
            .listItems(
              filter: ItemFilter(locationIds: repo.subtreeIds(kitchen.id)),
            )
            .map((i) => i.id),
        ['b', 'c'],
      );
    });
  });

  group('summary', () {
    test('is all zeroes for an empty inventory', () {
      final summary = repo.summary();

      expect(summary.total, 0);
      expect(summary.low, 0);
      expect(summary.out, 0);
      expect(summary.wanted, 0);
      expect(summary.sellable, 0);
      expect(summary.toBuy, 0);
    });

    test('counts each state', () async {
      await repo.upsert(itemFixture(id: 'ok', quantity: 5));
      await repo.upsert(itemFixture(id: 'low', quantity: 1, lowStockAt: 2));
      await repo.upsert(itemFixture(id: 'out', quantity: 0));
      await repo.upsert(
        itemFixture(id: 'want', quantity: 3, wanted: true, sellable: true),
      );

      final summary = repo.summary();
      expect(summary.total, 4);
      expect(summary.low, 1);
      expect(summary.out, 1);
      expect(summary.wanted, 1);
      expect(summary.sellable, 1);
      // low + out + wanted, with no double counting.
      expect(summary.toBuy, 3);
    });

    // An out-of-stock item that is also wanted must count once, which is why
    // toBuy is counted over items rather than summed from the other fields.
    test('does not double-count an item that is both out and wanted', () async {
      await repo.upsert(itemFixture(id: 'x', quantity: 0, wanted: true));

      expect(repo.summary().toBuy, 1);
    });
  });

  group('autocomplete sources', () {
    setUp(() async {
      await repo.upsert(
        itemFixture(
          id: 'a',
          room: 'Kitchen',
          container: 'Drawer',
          category: 'Food',
          unit: 'kg',
        ),
      );
      await repo.upsert(
        itemFixture(
          id: 'b',
          room: 'Kitchen',
          container: 'Drawer',
          category: 'Cables',
        ),
      );
      await repo.upsert(
        itemFixture(id: 'c', room: 'Shed', container: 'Crate'),
      );
    });

    test('ranks rooms by usage, then alphabetically', () {
      expect(repo.knownRooms(), ['Kitchen', 'Shed']);
    });

    test('breaks a usage tie alphabetically', () async {
      await repo.upsert(itemFixture(id: 'd', room: 'Attic'));

      expect(repo.knownRooms(), ['Kitchen', 'Attic', 'Shed']);
    });

    test('skips empty values', () async {
      await repo.upsert(itemFixture(id: 'e'));

      expect(repo.knownRooms(), isNot(contains('')));
    });

    test('containers can be scoped to one room', () {
      expect(repo.knownContainers(), ['Drawer', 'Crate']);
      expect(repo.knownContainers(room: 'Shed'), ['Crate']);
      expect(repo.knownContainers(room: 'shed'), ['Crate']);
    });

    test('exposes categories and units', () {
      expect(repo.knownCategories(), ['Cables', 'Food']);
      expect(repo.knownUnits(), ['kg']);
    });

    // The tree itself is covered in item_repository_locations_test.dart;
    // what matters here is that the seeded legacy strings became real places
    // on open, which is the path every existing install takes exactly once.
    test('the seeded legacy rooms have been folded into places', () async {
      await repo.runLocationMigration(now: DateTime.utc(2026, 8, 5));

      expect(
        repo.locationTree().map((n) => n.name).toSet(),
        containsAll(<String>['Kitchen', 'Shed']),
      );
    });
  });

  group('streams', () {
    // Creating an item is two log writes — the item, then its opening
    // adjustment — so the stream emits twice after one upsert. Asserted
    // exactly rather than loosely, so a future change to that write pattern
    // shows up here instead of as a mystery double rebuild.
    test('watchItems seeds immediately then re-emits on write', () async {
      final seen = <int>[];
      final sub = repo.watchItems().listen((items) => seen.add(items.length));
      await Future<void>.delayed(Duration.zero);

      await repo.upsert(itemFixture());
      await Future<void>.delayed(Duration.zero);

      expect(seen, [0, 1, 1]);
      await sub.cancel();
    });

    test('watchItems emits once when the write adds no adjustment', () async {
      final seen = <int>[];
      final sub = repo.watchItems().listen((items) => seen.add(items.length));
      await Future<void>.delayed(Duration.zero);

      await repo.upsert(itemFixture(quantity: 0));
      await Future<void>.delayed(Duration.zero);

      expect(seen, [0, 1]);
      await sub.cancel();
    });

    test('watchItem tracks one item', () async {
      await repo.upsert(itemFixture(name: 'First'));
      final seen = <String?>[];
      final sub = repo.watchItem('i1').listen((i) => seen.add(i?.name));
      await Future<void>.delayed(Duration.zero);

      await repo.upsert(itemFixture(name: 'Second'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['First', 'Second']);
      await sub.cancel();
    });

    test('watchSummary re-emits counts', () async {
      final seen = <int>[];
      final sub = repo.watchSummary().listen((s) => seen.add(s.total));
      await Future<void>.delayed(Duration.zero);

      await repo.upsert(itemFixture(quantity: 0));
      await Future<void>.delayed(Duration.zero);

      expect(seen, [0, 1]);
      await sub.cancel();
    });

    test('changes fires on every write', () async {
      var count = 0;
      final sub = repo.changes.listen((_) => count++);

      await repo.upsert(itemFixture());
      await Future<void>.delayed(Duration.zero);

      expect(count, greaterThan(0));
      await sub.cancel();
    });
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
          fields: {
            kTypeField: (kTypeItem, _hlc(1)),
            'name': ('Theirs', _hlc(1)),
          },
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
            kTypeField: (kTypeAdjustment, _hlc(1)),
            'item_id': ('i1', _hlc(1)),
            kAtField: (
              now.subtract(const Duration(days: 400)).toIso8601String(),
              _hlc(1),
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

  group('shopping lists', () {
    test('to-buy is a union of not-stocked and wanted', () async {
      await repo.upsert(itemFixture(id: 'ok', name: 'Fine', quantity: 9));
      await repo.upsert(itemFixture(id: 'out', name: 'Empty', quantity: 0));
      await repo.upsert(
        itemFixture(
          id: 'low',
          name: 'Nearly',
          quantity: 1,
          lowStockAt: 2,
        ),
      );
      await repo.upsert(
        itemFixture(id: 'want', name: 'Drill', quantity: 5, wanted: true),
      );

      final names = repo.listToBuy().map((item) => item.name).toSet();

      // 'Drill' is the load-bearing one: an AND of the two facets would drop
      // it, since it is fully stocked.
      expect(names, {'Empty', 'Nearly', 'Drill'});
      expect(names, isNot(contains('Fine')));
    });

    test('to-buy leads with what is actually out', () async {
      await repo.upsert(
        itemFixture(id: 'low', name: 'Nearly', quantity: 1, lowStockAt: 2),
      );
      await repo.upsert(itemFixture(id: 'out', name: 'Empty', quantity: 0));

      expect(repo.listToBuy().first.name, 'Empty');
    });

    test('to-buy honours an explicit sort', () async {
      await repo.upsert(itemFixture(id: 'b', name: 'Zinc', quantity: 0));
      await repo.upsert(itemFixture(id: 'a', name: 'Anchor', quantity: 0));

      final names = repo
          .listToBuy(sort: ItemSort.nameAsc)
          .map((item) => item.name)
          .toList();

      expect(names, ['Anchor', 'Zinc']);
    });

    test('sellable lists only flagged items, A-Z', () async {
      await repo.upsert(
        itemFixture(id: 'b', name: 'Zinc', sellable: true),
      );
      await repo.upsert(
        itemFixture(id: 'a', name: 'Anchor', sellable: true),
      );
      await repo.upsert(itemFixture(id: 'c', name: 'Keep'));

      final names = repo.listSellable().map((item) => item.name).toList();

      expect(names, ['Anchor', 'Zinc']);
    });

    test('sellable honours an explicit sort', () async {
      await repo.upsert(
        itemFixture(id: 'a', name: 'Anchor', quantity: 5, sellable: true),
      );
      await repo.upsert(
        itemFixture(id: 'b', name: 'Zinc', quantity: 1, sellable: true),
      );

      final names = repo
          .listSellable(sort: ItemSort.quantityAsc)
          .map((item) => item.name)
          .toList();

      expect(names, ['Zinc', 'Anchor']);
    });

    test('watchToBuy re-emits after a restock', () async {
      await repo.upsert(
        itemFixture(id: 'a', name: 'Flour', quantity: 0, lowStockAt: 1),
      );
      final seen = <int>[];
      final sub = repo.watchToBuy().listen((items) => seen.add(items.length));
      await pumpEventQueue();

      await repo.adjustQuantity('a', 3, AdjustmentSource.restock);
      await pumpEventQueue();
      await sub.cancel();

      // A restock writes twice — the item record and its adjustment — so the
      // assertion is on the ends of the sequence, not its length.
      expect(seen.first, 1);
      expect(seen.last, 0);
    });

    test('watchSellable re-emits after a flag change', () async {
      await repo.upsert(itemFixture(id: 'a', name: 'Monitor'));
      final seen = <int>[];
      final sub = repo.watchSellable().listen(
        (items) => seen.add(items.length),
      );
      await pumpEventQueue();

      await repo.upsert(itemFixture(id: 'a', name: 'Monitor', sellable: true));
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, 0);
      expect(seen.last, 1);
    });

    test('watchLocationTree re-emits after a place is added', () async {
      await repo.createLocation(name: 'Office', now: DateTime.utc(2026, 8, 5));
      final seen = <int>[];
      final sub = repo.watchLocationTree().listen(
        (places) => seen.add(places.length),
      );
      await pumpEventQueue();

      await repo.createLocation(name: 'Kitchen', now: DateTime.utc(2026, 8, 5));
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, 1);
      expect(seen.last, 2);
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

  group('best-before dates', () {
    final now = DateTime.utc(2026, 7, 26);

    test('a date survives the round trip through the log', () async {
      await repo.upsert(
        itemFixture(id: 'milk', bestBefore: DateTime.utc(2026, 7, 28)),
      );

      expect(repo.item('milk')!.bestBefore, DateTime.utc(2026, 7, 28));
    });

    // An epoch fallback would render every undated screwdriver as expired
    // since 1970, which is why the reader keeps null instead.
    test('no date reads back as null, not as the epoch', () async {
      await repo.upsert(itemFixture(id: 'driver'));

      expect(repo.item('driver')!.bestBefore, isNull);
    });

    test('unparseable stored text reads back as no date', () async {
      await repo.upsert(itemFixture(id: 'odd'));
      final existing = repo.exportLog()['odd']!;
      await repo.replaceAll({
        'odd': Record(
          id: 'odd',
          fields: {
            ...existing.fields,
            'best_before': ('not a date', existing.fields['name']!.$2),
          },
        ),
      });

      expect(repo.item('odd')!.bestBefore, isNull);
    });

    test('listExpiring returns overdue and due-soon, soonest first', () async {
      await repo.upsert(
        itemFixture(
          id: 'gone',
          name: 'Yoghurt',
          bestBefore: DateTime.utc(2026, 7, 20),
        ),
      );
      await repo.upsert(
        itemFixture(
          id: 'soon',
          name: 'Milk',
          bestBefore: DateTime.utc(2026, 7, 28),
        ),
      );
      await repo.upsert(
        itemFixture(id: 'later', name: 'Rice', bestBefore: DateTime.utc(2027)),
      );
      await repo.upsert(itemFixture(id: 'none', name: 'Hammer'));

      final expiring = repo.listExpiring(now: now);

      expect(expiring.map((i) => i.id), ['gone', 'soon']);
    });

    test('listExpiring falls back to the wall clock', () async {
      await repo.upsert(
        itemFixture(id: 'ancient', bestBefore: DateTime.utc(2000)),
      );

      expect(repo.listExpiring().map((i) => i.id), ['ancient']);
    });

    test('watchExpiring re-emits after a write', () async {
      final seen = <List<String>>[];
      final sub = repo
          .watchExpiring(now: now)
          .listen((items) => seen.add(items.map((i) => i.id).toList()));
      await pumpEventQueue();

      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, isEmpty);
      expect(seen.last, ['soon']);
    });

    test('listItems applies the freshness facet as of a given date', () async {
      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await repo.upsert(
        itemFixture(id: 'later', bestBefore: DateTime.utc(2027)),
      );

      final due = repo.listItems(
        filter: const ItemFilter(freshness: {FreshnessState.dueSoon}),
        asOf: now,
      );

      expect(due.map((i) => i.id), ['soon']);
    });

    test('watchItems threads the same clock through', () async {
      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await repo.upsert(itemFixture(id: 'undated'));

      final first = await repo
          .watchItems(
            filter: const ItemFilter(freshness: {FreshnessState.dueSoon}),
            asOf: now,
          )
          .first;

      expect(first.map((i) => i.id), ['soon']);
    });
  });

  group('the expiring-first sort', () {
    List<String> sorted() => repo
        .listItems(sort: ItemSort.expiringFirst)
        .map((i) => i.name)
        .toList();

    test('orders dated items by date and undated ones last', () async {
      await repo.upsert(
        itemFixture(id: 'b', name: 'Bread', bestBefore: DateTime.utc(2026, 8)),
      );
      await repo.upsert(itemFixture(id: 'h', name: 'Hammer'));
      await repo.upsert(
        itemFixture(id: 'm', name: 'Milk', bestBefore: DateTime.utc(2026, 7)),
      );

      expect(sorted(), ['Milk', 'Bread', 'Hammer']);
    });

    test('breaks ties on the same date by name', () async {
      final date = DateTime.utc(2026, 8);
      await repo.upsert(
        itemFixture(id: 'y', name: 'Yoghurt', bestBefore: date),
      );
      await repo.upsert(itemFixture(id: 'k', name: 'Kefir', bestBefore: date));

      expect(sorted(), ['Kefir', 'Yoghurt']);
    });

    test('breaks ties between undated items by name', () async {
      await repo.upsert(itemFixture(id: 's', name: 'Saw'));
      await repo.upsert(itemFixture(id: 'a', name: 'Awl'));

      expect(sorted(), ['Awl', 'Saw']);
    });
  });

  group('barcodes', () {
    setUp(() async {
      await repo.upsert(itemFixture(id: 'flour', name: 'Flour', unit: 'g'));
    });

    test('a linked code resolves to its item and amount', () async {
      await repo.linkBarcode(
        code: '5900512300153',
        itemId: 'flour',
        amount: 500,
        unit: 'g',
      );

      final link = repo.barcodeFor('5900512300153')!;

      expect(link.itemId, 'flour');
      expect(link.amount, 500);
      expect(link.unit, 'g');
    });

    test('a code is found however the scanner reported it', () async {
      await repo.linkBarcode(code: '0012345678905', itemId: 'flour');

      expect(repo.barcodeFor('012345678905')!.itemId, 'flour');
    });

    test('an unknown code resolves to nothing', () {
      expect(repo.barcodeFor('5900512300153'), isNull);
    });

    test('a blank code resolves to nothing', () {
      expect(repo.barcodeFor('  '), isNull);
    });

    test('a blank code cannot be linked', () async {
      expect(await repo.linkBarcode(code: ' ', itemId: 'flour'), isNull);
    });

    // A link worth nothing is one the user scans twice and then assumes is
    // broken.
    test('a non-positive amount cannot be linked', () async {
      expect(
        await repo.linkBarcode(code: '590', itemId: 'flour', amount: 0),
        isNull,
      );
    });

    test('linking the same code again replaces the mapping', () async {
      await repo.upsert(itemFixture(id: 'rice', name: 'Rice'));
      await repo.linkBarcode(code: '590', itemId: 'flour');
      await repo.linkBarcode(code: '590', itemId: 'rice');

      expect(repo.barcodeFor('590')!.itemId, 'rice');
      expect(repo.barcodesFor('flour'), isEmpty);
    });

    test('barcodesFor lists an item\'s codes in order', () async {
      await repo.linkBarcode(code: '592', itemId: 'flour');
      await repo.linkBarcode(code: '591', itemId: 'flour');
      await repo.upsert(itemFixture(id: 'rice'));
      await repo.linkBarcode(code: '593', itemId: 'rice');

      expect(repo.barcodesFor('flour').map((l) => l.code), ['591', '592']);
    });

    test('unlinking forgets the code', () async {
      await repo.linkBarcode(code: '590', itemId: 'flour');

      await repo.unlinkBarcode('590');

      expect(repo.barcodeFor('590'), isNull);
      expect(repo.barcodesFor('flour'), isEmpty);
    });

    test('a scan restocks by the linked amount', () async {
      await repo.linkBarcode(code: '590', itemId: 'flour', amount: 500);

      final item = await repo.applyScan(
        '590',
        source: AdjustmentSource.restock,
      );

      expect(item!.quantity, 501);
      expect(repo.historyFor('flour').last.source, AdjustmentSource.restock);
    });

    test(
      'a scan can consume instead, and the sign follows the source',
      () async {
        await repo.upsert(itemFixture(id: 'flour', quantity: 900, unit: 'g'));
        await repo.linkBarcode(code: '590', itemId: 'flour', amount: 500);

        final item = await repo.applyScan('590', source: AdjustmentSource.use);

        expect(item!.quantity, 400);
      },
    );

    test('scanning an unknown code changes nothing', () async {
      expect(
        await repo.applyScan('590', source: AdjustmentSource.restock),
        isNull,
      );
    });

    test('scanning a code whose item is gone changes nothing', () async {
      await repo.linkBarcode(code: '590', itemId: 'flour');
      await repo.delete('flour');

      expect(
        await repo.applyScan('590', source: AdjustmentSource.restock),
        isNull,
      );
    });

    // The whole reason isItemRecord is an allowlist rather than "not an
    // adjustment": a third kind must not surface as a phantom item.
    test('barcode records never surface as items', () async {
      await repo.linkBarcode(code: '590', itemId: 'flour');

      expect(repo.listItems().map((i) => i.id), ['flour']);
      expect(repo.item(BarcodeLink.recordId('590')), isNull);
    });

    test('an unlinked record is not resurrected by a lookup', () async {
      await repo.linkBarcode(code: '590', itemId: 'flour');
      await repo.unlinkBarcode('590');

      expect(repo.barcodesFor('flour'), isEmpty);
      expect(repo.barcodeFor('590'), isNull);
    });

    test(
      'a record missing its item id is ignored rather than crashing',
      () async {
        final hlc = repo.exportLog()['flour']!.fields['name']!.$2;
        await repo.replaceAll({
          ...repo.exportLog(),
          BarcodeLink.recordId('590'): Record(
            id: BarcodeLink.recordId('590'),
            fields: {
              'type': ('barcode', hlc),
              'code': ('590', hlc),
            },
          ),
        });

        expect(repo.barcodeFor('590'), isNull);
        expect(repo.barcodesFor('flour'), isEmpty);
      },
    );
  });
}
