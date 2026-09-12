import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';

import '../support/builders.dart';

void main() {
  group('matches — query', () {
    test('an empty query matches everything', () {
      expect(const ItemFilter().matches(itemFixture()), isTrue);
    });

    test('searches name, notes and category, case-insensitively', () {
      expect(
        const ItemFilter(query: 'CAB').matches(itemFixture(name: 'Cable')),
        isTrue,
      );
      expect(
        const ItemFilter(
          query: 'router',
        ).matches(itemFixture(notes: 'behind the Router')),
        isTrue,
      );
      expect(
        const ItemFilter(query: 'food').matches(itemFixture(category: 'Food')),
        isTrue,
      );
    });

    test('rejects an item matching none of the three', () {
      expect(
        const ItemFilter(query: 'zzz').matches(itemFixture(name: 'Cable')),
        isFalse,
      );
    });
  });
  group('matches — location and category facets', () {
    test('an empty facet does not restrict', () {
      expect(const ItemFilter().matches(itemFixture(room: 'Anywhere')), isTrue);
    });

    // Free text means "Cables" and "cables" can both exist; a chip for one
    // must pick up the other, or the list silently hides items.
    test('category folds case', () {
      final item = itemFixture(category: 'Cables');

      expect(const ItemFilter(categories: {'cables'}).matches(item), isTrue);
    });

    // Places match by exact id, deliberately unlike the free-text facets: an
    // id is not something the user typed, and the caller has already expanded
    // the selection to a whole subtree.
    test('a place matches by exact id', () {
      final item = itemFixture(locationId: 'loc1');

      expect(const ItemFilter(locationIds: {'loc1'}).matches(item), isTrue);
      expect(const ItemFilter(locationIds: {'LOC1'}).matches(item), isFalse);
    });

    test('a subtree selection matches anything filed in it', () {
      final onShelf = itemFixture(id: 'i1', locationId: 'shelf');
      final elsewhere = itemFixture(id: 'i2', locationId: 'kitchen');
      const filter = ItemFilter(locationIds: {'hall', 'shelf'});

      expect(filter.matches(onShelf), isTrue);
      expect(filter.matches(elsewhere), isFalse);
    });

    test('rejects an item outside each facet', () {
      final item = itemFixture(locationId: 'loc1', category: 'Cables');

      expect(const ItemFilter(locationIds: {'other'}).matches(item), isFalse);
      expect(const ItemFilter(categories: {'Food'}).matches(item), isFalse);
    });
  });
  group('matches — stock and flags', () {
    test('stock filters on the derived state', () {
      final low = itemFixture(quantity: 1, lowStockAt: 2);

      expect(const ItemFilter(stock: {StockState.low}).matches(low), isTrue);
      expect(const ItemFilter(stock: {StockState.ok}).matches(low), isFalse);
    });

    test('flags AND together', () {
      final both = itemFixture(wanted: true, sellable: true);
      final wantedOnly = itemFixture(wanted: true);

      const filter = ItemFilter(flags: {ItemFlag.wanted, ItemFlag.sellable});

      expect(filter.matches(both), isTrue);
      expect(filter.matches(wantedOnly), isFalse);
    });

    test('each flag is checked independently', () {
      expect(
        const ItemFilter(
          flags: {ItemFlag.wanted},
        ).matches(itemFixture(sellable: true)),
        isFalse,
      );
      expect(
        const ItemFilter(
          flags: {ItemFlag.sellable},
        ).matches(itemFixture(wanted: true)),
        isFalse,
      );
    });
  });
}
