import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/record_types.dart';

Hlc _hlc(int ms) => Hlc(wallTimeMs: ms, counter: 0, nodeId: 'n');

Record _adjustment(String id, DateTime at) => Record(
  id: id,
  fields: {
    kTypeField: (kTypeAdjustment, _hlc(1)),
    kAtField: (at.toIso8601String(), _hlc(1)),
  },
);

Record _item(String id, {bool deleted = false}) => Record(
  id: id,
  fields: {kTypeField: (kTypeItem, _hlc(1))},
  deleted: deleted,
  deletedHlc: deleted ? _hlc(2) : null,
);

void main() {
  final now = DateTime.utc(2026, 7, 26);
  final ancient = now.subtract(const Duration(days: 400));
  final recent = now.subtract(const Duration(days: 10));

  group('isAdjustmentRecord', () {
    test('recognises an adjustment', () {
      expect(isAdjustmentRecord(_adjustment('a', recent)), isTrue);
    });

    test('an item is not an adjustment', () {
      expect(isAdjustmentRecord(_item('i')), isFalse);
    });

    // A record kind written by a newer build must survive a round-trip
    // through an older one, so anything unrecognised reads as an item — the
    // kind that is never pruned.
    test('an unknown or missing type reads as an item', () {
      final unknown = Record(
        id: 'x',
        fields: {kTypeField: ('quantum-widget', _hlc(1))},
      );
      final typeless = Record(id: 'y', fields: {'name': ('hi', _hlc(1))});

      expect(isAdjustmentRecord(unknown), isFalse);
      expect(isAdjustmentRecord(typeless), isFalse);
    });
  });

  group('dropAncientAdjustments', () {
    test('drops an adjustment past the horizon', () {
      final log = {'a': _adjustment('a', ancient)};

      expect(dropAncientAdjustments(log, now), isEmpty);
    });

    test('keeps an adjustment inside the horizon', () {
      final log = {'a': _adjustment('a', recent)};

      expect(dropAncientAdjustments(log, now).keys, ['a']);
    });

    test('keeps one exactly at the horizon', () {
      final edge = now.subtract(kAdjustmentHorizon);
      final log = {'a': _adjustment('a', edge)};

      expect(dropAncientAdjustments(log, now).keys, ['a']);
    });

    // Dropping an item tombstone resurrects a deleted item on a device that
    // has been offline long enough — user-visible harm, unlike an ancient
    // adjustment briefly reappearing.
    test('never drops an item, however old, tombstoned or not', () {
      final log = {
        'live': _item('live'),
        'gone': _item('gone', deleted: true),
      };

      expect(dropAncientAdjustments(log, now).keys, ['live', 'gone']);
    });

    test('keeps an adjustment with an unparseable timestamp', () {
      final log = {
        'a': Record(
          id: 'a',
          fields: {
            kTypeField: (kTypeAdjustment, _hlc(1)),
            kAtField: ('not-a-date', _hlc(1)),
          },
        ),
      };

      expect(dropAncientAdjustments(log, now).keys, ['a']);
    });

    test('keeps an adjustment with a non-string timestamp', () {
      final log = {
        'a': Record(
          id: 'a',
          fields: {
            kTypeField: (kTypeAdjustment, _hlc(1)),
            kAtField: (12345, _hlc(1)),
          },
        ),
      };

      expect(dropAncientAdjustments(log, now).keys, ['a']);
    });

    test('keeps an adjustment with no timestamp field at all', () {
      final log = {
        'a': Record(
          id: 'a',
          fields: {kTypeField: (kTypeAdjustment, _hlc(1))},
        ),
      };

      expect(dropAncientAdjustments(log, now).keys, ['a']);
    });

    test('is idempotent', () {
      final log = {
        'old': _adjustment('old', ancient),
        'new': _adjustment('new', recent),
      };

      final once = dropAncientAdjustments(log, now);

      expect(dropAncientAdjustments(once, now), once);
    });

    // The property the whole retention design rests on: because the
    // predicate reads only each record's own immutable content, a pruned log
    // and an unpruned one converge to the same thing however they are
    // merged, and the ancient record never comes back.
    test('converges regardless of which side pruned first', () {
      final full = {
        'old': _adjustment('old', ancient),
        'new': _adjustment('new', recent),
        'item': _item('item'),
      };
      final pruned = dropAncientAdjustments(full, now);

      final aThenB = dropAncientAdjustments(mergeLogs(pruned, full), now);
      final bThenA = dropAncientAdjustments(mergeLogs(full, pruned), now);

      expect(aThenB.keys.toSet(), bThenA.keys.toSet());
      expect(aThenB.containsKey('old'), isFalse);
      expect(aThenB.keys.toSet(), {'new', 'item'});
    });
  });
}
