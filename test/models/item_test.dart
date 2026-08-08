import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';

import '../support/builders.dart';

void main() {
  group('stockState', () {
    test('is out at zero regardless of the threshold', () {
      expect(itemFixture(quantity: 0).stockState, StockState.out);
      expect(
        itemFixture(quantity: 0, lowStockAt: 5).stockState,
        StockState.out,
      );
    });

    // A negative quantity should not be reachable through the repository,
    // which clamps — but a hand-written record could carry one.
    test('is out below zero', () {
      expect(itemFixture(quantity: -3).stockState, StockState.out);
    });

    test('is ok when no threshold is set, however little is left', () {
      expect(itemFixture(quantity: 0.1).stockState, StockState.ok);
    });

    test('is low exactly at the threshold, not just below it', () {
      expect(
        itemFixture(quantity: 2, lowStockAt: 2).stockState,
        StockState.low,
      );
      expect(
        itemFixture(quantity: 1.5, lowStockAt: 2).stockState,
        StockState.low,
      );
    });

    test('is ok above the threshold', () {
      expect(
        itemFixture(quantity: 2.5, lowStockAt: 2).stockState,
        StockState.ok,
      );
    });
  });

  group('legacyLocation', () {
    test('joins room and container', () {
      final item = itemFixture(room: 'Kitchen', container: 'Top drawer');

      expect(item.legacyLocation, 'Kitchen › Top drawer');
    });

    test('omits an empty part rather than leaving a dangling separator', () {
      expect(itemFixture(room: 'Kitchen').legacyLocation, 'Kitchen');
      expect(itemFixture(container: 'Box A').legacyLocation, 'Box A');
      expect(itemFixture().legacyLocation, '');
    });
  });

  group('needsBuying', () {
    test('is true for anything not fully stocked', () {
      expect(itemFixture(quantity: 0).needsBuying, isTrue);
      expect(
        itemFixture(quantity: 1, lowStockAt: 2).needsBuying,
        isTrue,
      );
    });

    test('is true for a wanted item even when stocked', () {
      expect(itemFixture(quantity: 10, wanted: true).needsBuying, isTrue);
    });

    test('is false for a stocked, unwanted item', () {
      expect(itemFixture(quantity: 10).needsBuying, isFalse);
    });
  });

  group('copyWith', () {
    test('replaces only the named fields', () {
      final base = itemFixture(name: 'Old', quantity: 1, room: 'Kitchen');

      final updated = base.copyWith(name: 'New', quantity: 3);

      expect(updated.id, base.id);
      expect(updated.name, 'New');
      expect(updated.quantity, 3);
      expect(updated.room, 'Kitchen');
    });

    test('leaves everything alone when given nothing', () {
      final base = itemFixture(
        name: 'Thing',
        unit: 'kg',
        container: 'Box',
        category: 'Food',
        lowStockAt: 2,
        wanted: true,
        sellable: true,
        notes: 'note',
      );

      final copy = base.copyWith();

      expect(copy.name, base.name);
      expect(copy.unit, base.unit);
      expect(copy.container, base.container);
      expect(copy.category, base.category);
      expect(copy.lowStockAt, base.lowStockAt);
      expect(copy.wanted, base.wanted);
      expect(copy.sellable, base.sellable);
      expect(copy.notes, base.notes);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
    });

    test('replaces each remaining field', () {
      final base = itemFixture();
      final created = DateTime.utc(2025, 5);
      final updated = DateTime.utc(2025, 6);

      final copy = base.copyWith(
        unit: 'kg',
        room: 'Shed',
        container: 'Crate',
        category: 'Tools',
        wanted: true,
        sellable: true,
        notes: 'hi',
        createdAt: created,
        updatedAt: updated,
      );

      expect(copy.unit, 'kg');
      expect(copy.room, 'Shed');
      expect(copy.container, 'Crate');
      expect(copy.category, 'Tools');
      expect(copy.wanted, isTrue);
      expect(copy.sellable, isTrue);
      expect(copy.notes, 'hi');
      expect(copy.createdAt, created);
      expect(copy.updatedAt, updated);
    });

    // Null means "unchanged", so clearing a nullable needs its own flag.
    test('clearLowStockAt is the only way to unset the threshold', () {
      final base = itemFixture(lowStockAt: 4);

      expect(base.copyWith(lowStockAt: null).lowStockAt, 4);
      expect(base.copyWith(clearLowStockAt: true).lowStockAt, isNull);
    });

    test('clearLowStockAt wins over a supplied value', () {
      final base = itemFixture(lowStockAt: 4);

      expect(
        base.copyWith(lowStockAt: 9, clearLowStockAt: true).lowStockAt,
        isNull,
      );
    });
  });

  group('formatQuantity', () {
    test('drops the decimal for whole amounts', () {
      expect(formatQuantity(4), '4');
      expect(formatQuantity(0), '0');
    });

    test('keeps the decimal for fractional amounts', () {
      expect(formatQuantity(2.5), '2.5');
    });
  });

  test('toString names the item and where it is filed', () {
    final item = itemFixture(
      name: 'Flour',
      quantity: 2.5,
      unit: 'kg',
      locationId: 'loc1',
    );

    expect(item.toString(), contains('Flour'));
    // The id rather than a name: resolving the path needs the other records,
    // which a model cannot reach.
    expect(item.toString(), contains('loc1'));
  });

  group('freshnessAt', () {
    test('an undated item has no reading at all', () {
      expect(itemFixture().freshnessAt(DateTime.utc(2026, 7, 26)), isNull);
    });

    test('a dated item reads against the supplied clock', () {
      final item = itemFixture(bestBefore: DateTime.utc(2026, 7, 27));

      final freshness = item.freshnessAt(DateTime.utc(2026, 7, 26))!;

      expect(freshness.daysLeft, 1);
      expect(freshness.state, FreshnessState.dueSoon);
    });
  });

  group('copyWith and bestBefore', () {
    test('replaces the date', () {
      final item = itemFixture(bestBefore: DateTime.utc(2026));

      final moved = item.copyWith(bestBefore: DateTime.utc(2027));

      expect(moved.bestBefore, DateTime.utc(2027));
    });

    test('a null argument leaves the date alone', () {
      final item = itemFixture(bestBefore: DateTime.utc(2026));

      expect(item.copyWith(name: 'Other').bestBefore, DateTime.utc(2026));
    });

    // Same reason `clearLowStockAt` exists: null already means "unchanged",
    // so removing a date needs its own flag.
    test('clearBestBefore removes it', () {
      final item = itemFixture(bestBefore: DateTime.utc(2026));

      expect(item.copyWith(clearBestBefore: true).bestBefore, isNull);
    });
  });
}
