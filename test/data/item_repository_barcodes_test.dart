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
            fields: {'type': ('barcode', hlc), 'code': ('590', hlc)},
          ),
        });

        expect(repo.barcodeFor('590'), isNull);
        expect(repo.barcodesFor('flour'), isEmpty);
      },
    );
  });
}
