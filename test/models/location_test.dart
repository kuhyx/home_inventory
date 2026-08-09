import 'package:flutter_test/flutter_test.dart';

import '../support/builders.dart';

void main() {
  group('Location', () {
    test('isRoot is true only at the top level', () {
      expect(locationFixture().isRoot, isTrue);
      expect(locationFixture(parentId: 'p').isRoot, isFalse);
    });

    test('copyWith replaces only the named fields', () {
      final original = locationFixture(name: 'Korytarz', parentId: 'p');

      final renamed = original.copyWith(name: 'Hall');

      expect(renamed.name, 'Hall');
      expect(renamed.id, original.id);
      expect(renamed.parentId, 'p');
      expect(renamed.sortKey, original.sortKey);
    });

    // Null means "leave unchanged" everywhere else in this codebase, so moving
    // a place *to* the top level cannot be expressed by passing null — hence
    // the explicit flag, same as Item.clearLowStockAt.
    test('clearParentId is the only way to move to the top level', () {
      final nested = locationFixture(parentId: 'p');

      expect(nested.copyWith().parentId, 'p');
      expect(nested.copyWith(parentId: null).parentId, 'p');
      expect(nested.copyWith(clearParentId: true).parentId, isNull);
    });

    test('clearParentId wins over a supplied parentId', () {
      final nested = locationFixture(parentId: 'p');

      expect(
        nested.copyWith(parentId: 'other', clearParentId: true).parentId,
        isNull,
      );
    });

    test('toString names the place and its parent', () {
      final text = locationFixture(name: 'Korytarz', parentId: 'p').toString();

      expect(text, contains('Korytarz'));
      expect(text, contains('p'));
    });
  });
}
