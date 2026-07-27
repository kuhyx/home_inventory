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
      expect(const ItemFilter(rooms: {'Kitchen'}).isEmpty, isFalse);
      expect(const ItemFilter(containers: {'Box'}).isEmpty, isFalse);
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
      const filter = ItemFilter(rooms: {'Kitchen', 'Shed', 'Loft'});

      expect(filter.activeCount, 1);
    });

    test('counts every facet in use', () {
      const filter = ItemFilter(
        query: 'cable',
        rooms: {'Kitchen'},
        containers: {'Box'},
        categories: {'Cables'},
        stock: {StockState.low},
        flags: {ItemFlag.wanted},
      );

      expect(filter.activeCount, 6);
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
    test('room, container and category all fold case', () {
      final item = itemFixture(
        room: 'Kitchen',
        container: 'Top Drawer',
        category: 'Cables',
      );

      expect(const ItemFilter(rooms: {'kitchen'}).matches(item), isTrue);
      expect(
        const ItemFilter(containers: {'top drawer'}).matches(item),
        isTrue,
      );
      expect(
        const ItemFilter(categories: {'cables'}).matches(item),
        isTrue,
      );
    });

    test('rejects an item outside each facet', () {
      final item = itemFixture(
        room: 'Kitchen',
        container: 'Top Drawer',
        category: 'Cables',
      );

      expect(const ItemFilter(rooms: {'Shed'}).matches(item), isFalse);
      expect(const ItemFilter(containers: {'Crate'}).matches(item), isFalse);
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
      const base = ItemFilter(query: 'a', rooms: {'Kitchen'});

      final copy = base.copyWith();

      expect(copy.query, 'a');
      expect(copy.rooms, {'Kitchen'});
    });

    test('an empty set clears a facet', () {
      const base = ItemFilter(rooms: {'Kitchen'});

      expect(base.copyWith(rooms: {}).rooms, isEmpty);
    });

    test('replaces every facet', () {
      const base = ItemFilter();

      final copy = base.copyWith(
        query: 'q',
        rooms: {'r'},
        containers: {'c'},
        categories: {'cat'},
        stock: {StockState.out},
        flags: {ItemFlag.sellable},
      );

      expect(copy.query, 'q');
      expect(copy.rooms, {'r'});
      expect(copy.containers, {'c'});
      expect(copy.categories, {'cat'});
      expect(copy.stock, {StockState.out});
      expect(copy.flags, {ItemFlag.sellable});
    });
  });

  group('value equality', () {
    test('two filters with equal facets are equal', () {
      const a = ItemFilter(query: 'q', rooms: {'Office', 'Kitchen'});
      const b = ItemFilter(query: 'q', rooms: {'Kitchen', 'Office'});

      expect(a, b);
      // Sets are unordered, so their own hashCode is identity-based: without
      // the commutative fold these two would hash differently and a Set or Map
      // of filters would hold both.
      expect(a.hashCode, b.hashCode);
    });

    test('a differing facet breaks equality', () {
      const a = ItemFilter(rooms: {'Office'});
      const b = ItemFilter(rooms: {'Kitchen'});

      expect(a, isNot(b));
    });

    test('a facet of a different size breaks equality', () {
      const a = ItemFilter(rooms: {'Office'});
      const b = ItemFilter(rooms: {'Office', 'Kitchen'});

      expect(a, isNot(b));
    });

    test('every facet participates', () {
      const base = ItemFilter();

      expect(base, isNot(const ItemFilter(query: 'q')));
      expect(base, isNot(const ItemFilter(rooms: {'r'})));
      expect(base, isNot(const ItemFilter(containers: {'c'})));
      expect(base, isNot(const ItemFilter(categories: {'cat'})));
      expect(base, isNot(const ItemFilter(stock: {StockState.out})));
      expect(base, isNot(const ItemFilter(flags: {ItemFlag.wanted})));
    });

    test('is not equal to another type', () {
      expect(const ItemFilter(), isNot('not a filter'));
    });
  });
}
