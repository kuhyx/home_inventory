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
      final updated = await repo.setQuantity('i1', 9, AdjustmentSource.restock);

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
      expect(await repo.setQuantity('nope', 1, AdjustmentSource.use), isNull);
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
}
