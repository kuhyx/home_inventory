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
  group('shopping lists', () {
    test('to-buy is a union of not-stocked and wanted', () async {
      await repo.upsert(itemFixture(id: 'ok', name: 'Fine', quantity: 9));
      await repo.upsert(itemFixture(id: 'out', name: 'Empty', quantity: 0));
      await repo.upsert(
        itemFixture(id: 'low', name: 'Nearly', quantity: 1, lowStockAt: 2),
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
      await repo.upsert(itemFixture(id: 'b', name: 'Zinc', sellable: true));
      await repo.upsert(itemFixture(id: 'a', name: 'Anchor', sellable: true));
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
}
