import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/derived_ids.dart';

void main() {
  group('foldKey', () {
    test('trims, lowercases and collapses inner whitespace', () {
      expect(foldKey('  Szafka   z  Lewej '), 'szafka z lewej');
    });

    test('leaves an already-folded value alone', () {
      expect(foldKey('kuchnia'), 'kuchnia');
    });
  });

  group('derivedLocationId', () {
    test('the same parent and name always give the same id', () {
      expect(
        derivedLocationId(null, 'Korytarz'),
        derivedLocationId(null, 'Korytarz'),
      );
    });

    // The whole point: two devices that mint "Kitchen" while offline have to
    // land on one record, or the first sync doubles every room in the house.
    test('folding means casing and spacing cannot fork a place', () {
      final canonical = derivedLocationId(null, 'Szafka z lewej');

      expect(derivedLocationId(null, 'szafka z lewej'), canonical);
      expect(derivedLocationId(null, '  SZAFKA   Z LEWEJ  '), canonical);
    });

    test('the same name under different parents gives different ids', () {
      expect(
        derivedLocationId('a', 'Półka'),
        isNot(derivedLocationId('b', 'Półka')),
      );
    });

    test('a top-level name differs from the same name nested', () {
      expect(
        derivedLocationId(null, 'Półka'),
        isNot(derivedLocationId('a', 'Półka')),
      );
    });

    // A golden, deliberately pinned to a literal. These ids are already in
    // users' logs and on their other devices: if a refactor of [foldKey] or
    // the namespace changes what this returns, every existing place silently
    // becomes a different record and the tree splits in two. That has to fail
    // here, loudly, rather than on a phone after a sync.
    test('is stable against a pinned literal', () {
      expect(
        derivedLocationId(null, 'Korytarz'),
        'b077dca8-4cbe-5524-b305-3448ed5e0c4f',
      );
    });
  });

  group('derivedItemTypeId', () {
    test('the same slug always gives the same id', () {
      expect(derivedItemTypeId('books'), derivedItemTypeId('books'));
    });

    test('different slugs give different ids', () {
      expect(derivedItemTypeId('books'), isNot(derivedItemTypeId('rtv')));
    });

    test('does not collide with a location of the same name', () {
      expect(
        derivedItemTypeId('books'),
        isNot(derivedLocationId(null, 'books')),
      );
    });
  });
}
