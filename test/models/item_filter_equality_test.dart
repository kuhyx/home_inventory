import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';

import '../support/builders.dart';

void main() {
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
  group('the freshness facet', () {
    final now = DateTime.utc(2026, 7, 26);
    final dueSoon = itemFixture(
      id: 'soon',
      bestBefore: DateTime.utc(2026, 7, 27),
    );
    final fresh = itemFixture(id: 'fresh', bestBefore: DateTime.utc(2027));
    final undated = itemFixture(id: 'undated');

    test('keeps items in a selected state', () {
      const filter = ItemFilter(freshness: {FreshnessState.dueSoon});

      expect(filter.matches(dueSoon, asOf: now), isTrue);
    });

    test('drops items in every other state', () {
      const filter = ItemFilter(freshness: {FreshnessState.dueSoon});

      expect(filter.matches(fresh, asOf: now), isFalse);
    });

    // "Due soon" is a question about the things you dated. Answering it with
    // every screwdriver in the flat would make the facet useless.
    test('excludes undated items entirely', () {
      const filter = ItemFilter(freshness: {FreshnessState.fresh});

      expect(filter.matches(undated, asOf: now), isFalse);
    });

    test('an empty facet ignores the date and the clock', () {
      expect(const ItemFilter().matches(undated), isTrue);
      expect(const ItemFilter().matches(dueSoon), isTrue);
    });

    // Exercises the default clock: a date far enough out is fresh whenever
    // this test happens to run.
    test('falls back to now when no clock is given', () {
      const filter = ItemFilter(freshness: {FreshnessState.fresh});
      final farOut = itemFixture(bestBefore: DateTime(2999));

      expect(filter.matches(farOut), isTrue);
    });

    test('counts as one active restriction', () {
      const filter = ItemFilter(freshness: {FreshnessState.expired});

      expect(filter.activeCount, 1);
      expect(filter.isEmpty, isFalse);
    });

    test('takes part in equality and hashing', () {
      const a = ItemFilter(freshness: {FreshnessState.expired});
      const b = ItemFilter(freshness: {FreshnessState.expired});
      const c = ItemFilter(freshness: {FreshnessState.fresh});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces it and leaves it alone when null', () {
      const filter = ItemFilter(freshness: {FreshnessState.expired});

      expect(filter.copyWith(freshness: {FreshnessState.fresh}).freshness, {
        FreshnessState.fresh,
      });
      expect(filter.copyWith(query: 'x').freshness, {FreshnessState.expired});
    });
  });
}
