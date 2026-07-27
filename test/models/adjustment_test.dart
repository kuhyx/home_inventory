import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/adjustment.dart';

void main() {
  group('AdjustmentSource.fromWire', () {
    test('round-trips every known source', () {
      for (final source in AdjustmentSource.values) {
        expect(AdjustmentSource.fromWire(source.wire), source);
      }
    });

    // The fallback is `correction` specifically because that is the source
    // excluded from the rate — an unreadable record can only make the
    // projection quieter, never wilder.
    test('falls back to correction for an unknown wire value', () {
      expect(
        AdjustmentSource.fromWire('teleported'),
        AdjustmentSource.correction,
      );
    });

    test('falls back to correction for a missing wire value', () {
      expect(AdjustmentSource.fromWire(null), AdjustmentSource.correction);
    });
  });

  group('consumed', () {
    test('is the magnitude of a decrease', () {
      final adjustment = Adjustment(
        id: 'a1',
        itemId: 'i1',
        delta: -3,
        at: DateTime.utc(2026),
        source: AdjustmentSource.use,
      );

      expect(adjustment.consumed, 3);
    });

    test('is zero for an increase or a no-op', () {
      final restock = Adjustment(
        id: 'a1',
        itemId: 'i1',
        delta: 5,
        at: DateTime.utc(2026),
        source: AdjustmentSource.restock,
      );

      expect(restock.consumed, 0);
    });
  });

  test('toString names the item, delta and source', () {
    final adjustment = Adjustment(
      id: 'a1',
      itemId: 'i1',
      delta: -1,
      at: DateTime.utc(2026),
      source: AdjustmentSource.use,
    );

    expect(adjustment.toString(), contains('i1'));
    expect(adjustment.toString(), contains('use'));
  });
}
