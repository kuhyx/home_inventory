import 'package:flutter_test/flutter_test.dart';
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
      expect(
        const ItemFilter(stock: {StockState.low}).isEmpty,
        isFalse,
      );
      expect(
        const ItemFilter(flags: {ItemFlag.wanted}).isEmpty,
        isFalse,
      );
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
      expect(
        const ItemFilter().matches(itemFixture(room: 'Anywhere')),
        isTrue,
      );
    });

    // Free text means "Cables" and "cables" can both exist; a chip for one
    // must pick up the other, or the list silently hides items.
    test('category folds case', () {
      final item = itemFixture(category: 'Cables');

      expect(
        const ItemFilter(categories: {'cables'}).matches(item),
        isTrue,
      );
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

      expect(
        const ItemFilter(stock: {StockState.low}).matches(low),
        isTrue,
      );
      expect(
        const ItemFilter(stock: {StockState.ok}).matches(low),
        isFalse,
      );
    });

    test('flags AND together', () {
      final both = itemFixture(wanted: true, sellable: true);
      final wantedOnly = itemFixture(wanted: true);

      const filter = ItemFilter(
        flags: {ItemFlag.wanted, ItemFlag.sellable},
      );

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

  group('copyWith', () {
    test('null leaves a facet unchanged', () {
      const base = ItemFilter(query: 'a', locationIds: {'loc1'});

      final copy = base.copyWith();

      expect(copy.query, 'a');
      expect(copy.locationIds, {'loc1'});
    });

    test('an empty set clears a facet', () {
      const base = ItemFilter(locationIds: {'loc1'});

      expect(base.copyWith(locationIds: {}).locationIds, isEmpty);
    });

    test('replaces every facet', () {
      const base = ItemFilter();

      final copy = base.copyWith(
        query: 'q',
        locationIds: {'r'},
        categories: {'cat'},
        stock: {StockState.out},
        flags: {ItemFlag.sellable},
      );

      expect(copy.query, 'q');
      expect(copy.locationIds, {'r'});
      expect(copy.categories, {'cat'});
      expect(copy.stock, {StockState.out});
      expect(copy.flags, {ItemFlag.sellable});
    });
  });

  group('value equality', () {
    test('two filters with equal facets are equal', () {
      const a = ItemFilter(query: 'q', locationIds: {'b', 'a'});
      const b = ItemFilter(query: 'q', locationIds: {'a', 'b'});

      expect(a, b);
      // Sets are unordered, so their own hashCode is identity-based: without
      // the commutative fold these two would hash differently and a Set or Map
      // of filters would hold both.
      expect(a.hashCode, b.hashCode);
    });

    test('a differing facet breaks equality', () {
      const a = ItemFilter(locationIds: {'a'});
      const b = ItemFilter(locationIds: {'b'});

      expect(a, isNot(b));
    });

    test('a facet of a different size breaks equality', () {
      const a = ItemFilter(locationIds: {'a'});
      const b = ItemFilter(locationIds: {'a', 'b'});

      expect(a, isNot(b));
    });

    test('every facet participates', () {
      const base = ItemFilter();

      expect(base, isNot(const ItemFilter(query: 'q')));
      expect(base, isNot(const ItemFilter(locationIds: {'r'})));
      expect(base, isNot(const ItemFilter(categories: {'cat'})));
      expect(base, isNot(const ItemFilter(stock: {StockState.out})));
      expect(base, isNot(const ItemFilter(flags: {ItemFlag.wanted})));
    });

    test('is not equal to another type', () {
      expect(const ItemFilter(), isNot('not a filter'));
    });
  });
}
