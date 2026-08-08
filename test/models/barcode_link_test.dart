import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/barcode_link.dart';

void main() {
  group('normalizeBarcode', () {
    test('trims what a scanner or a paste leaves behind', () {
      expect(BarcodeLink.normalizeBarcode('  5900512300153 '), '5900512300153');
    });

    // Two phones can report the same tin as a 12-digit UPC-A and as the
    // 13-digit EAN that starts with a zero. Without folding them, a household
    // ends up with two mappings for one tin and half its scans miss.
    test('pads a 12-digit UPC-A onto its EAN-13 form', () {
      expect(BarcodeLink.normalizeBarcode('012345678905'), '0012345678905');
    });

    test('leaves a 13-digit code alone', () {
      expect(BarcodeLink.normalizeBarcode('5900512300153'), '5900512300153');
    });

    // QR labels are not GTINs; padding one would change what it points at.
    test('does not pad a 12-character non-numeric code', () {
      expect(BarcodeLink.normalizeBarcode('SHELF-BIN-04'), 'SHELF-BIN-04');
    });

    test('blank stays blank', () {
      expect(BarcodeLink.normalizeBarcode('   '), '');
    });
  });

  // A uuid here would let two devices that scan the same unknown bag each
  // keep their own mapping, and a lookup would have to choose between two
  // records that both claim the code.
  test('recordId is a pure function of the code', () {
    expect(
      BarcodeLink.recordId('5900512300153'),
      BarcodeLink.recordId('5900512300153'),
    );
    expect(
      BarcodeLink.recordId('5900512300153'),
      isNot(BarcodeLink.recordId('5900512300154')),
    );
  });

  group('toString', () {
    test('names the code, the item and the amount', () {
      const link = BarcodeLink(
        code: '590',
        itemId: 'flour',
        amount: 500,
        unit: 'g',
      );

      expect(link.toString(), contains('590 -> flour'));
      expect(link.toString(), contains('+500.0 g'));
    });

    test('omits an empty unit rather than trailing a space', () {
      const link = BarcodeLink(
        code: '590',
        itemId: 'cable',
        amount: 1,
        unit: '',
      );

      expect(link.toString(), endsWith('+1.0)'));
    });
  });
}
