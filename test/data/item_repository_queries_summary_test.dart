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
      await repo.upsert(itemFixture(id: 'c', room: 'Shed', container: 'Crate'));
    });

    test('ranks values by usage, then alphabetically', () async {
      await repo.upsert(itemFixture(id: 'd', category: 'Food'));

      expect(repo.knownCategories(), ['Food', 'Cables']);
    });

    test('skips empty values', () async {
      await repo.upsert(itemFixture(id: 'e'));

      expect(repo.knownCategories(), isNot(contains('')));
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
}
