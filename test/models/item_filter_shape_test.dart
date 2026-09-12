import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';

import '../support/builders.dart';

void main() {
  group('isEmpty', () {
    test('a default filter restricts nothing', () {
      expect(const ItemFilter().isEmpty, isTrue);
    });

    test('whitespace-only query still counts as empty', () {
      expect(const ItemFilter(query: '   ').isEmpty, isTrue);
    });

    test('any populated facet makes it non-empty', () {
      expect(const ItemFilter(query: 'a').isEmpty, isFalse);
      expect(const ItemFilter(locationIds: {'loc1'}).isEmpty, isFalse);
      expect(const ItemFilter(categories: {'Food'}).isEmpty, isFalse);
      expect(const ItemFilter(stock: {StockState.low}).isEmpty, isFalse);
      expect(const ItemFilter(flags: {ItemFlag.wanted}).isEmpty, isFalse);
    });
  });
  group('activeCount', () {
    test('is zero for a default filter', () {
      expect(const ItemFilter().activeCount, 0);
    });

    // Counts facets, not selections: three rooms is one restriction as far
    // as the user is concerned, so the badge should read 1.
    test('counts facets rather than selections', () {
      const filter = ItemFilter(locationIds: {'a', 'b', 'c'});

      expect(filter.activeCount, 1);
    });

    test('counts every facet in use', () {
      const filter = ItemFilter(
        query: 'cable',
        locationIds: {'loc1'},
        categories: {'Cables'},
        stock: {StockState.low},
        flags: {ItemFlag.wanted},
      );

      // Five, not six: rooms and containers became one place facet.
      expect(filter.activeCount, 5);
    });

    test('ignores a whitespace-only query', () {
      expect(const ItemFilter(query: '  ').activeCount, 0);
    });
  });
}
