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
      expect(repo.listItems(sort: ItemSort.nameAsc).map((i) => i.id), [
        'b',
        'c',
        'a',
      ]);
    });

    test('sorts by creation date', () {
      expect(repo.listItems(sort: ItemSort.createdDesc).map((i) => i.id), [
        'c',
        'b',
        'a',
      ]);
    });

    test('sorts scarcest first', () {
      expect(repo.listItems(sort: ItemSort.quantityAsc).map((i) => i.id), [
        'c',
        'b',
        'a',
      ]);
    });

    test('sorts by location, then name', () {
      expect(repo.listItems(sort: ItemSort.locationAsc).map((i) => i.id), [
        'b',
        'c',
        'a',
      ]);
    });

    test('sorts out, then low, then fine', () {
      expect(repo.listItems(sort: ItemSort.lowStockFirst).map((i) => i.id), [
        'c',
        'b',
        'a',
      ]);
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
      await repo.upsert(itemFixture(id: 'f', name: 'Aspirin', quantity: 0));

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
}
