import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/derived_ids.dart';
import 'package:home_inventory/data/location_migration.dart';
import 'package:home_inventory/models/location.dart';

import '../support/builders.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  group('planLocationMigration', () {
    test('folds a room and container into a two-level tree', () {
      final plan = planLocationMigration(
        [itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka')],
        const [],
        now,
      );

      final roomId = derivedLocationId(null, 'Korytarz');
      final shelfId = derivedLocationId(roomId, 'Szafka');

      expect(plan.locations.map((l) => l.id), [roomId, shelfId]);
      expect(plan.locations.first.parentId, isNull);
      expect(plan.locations.last.parentId, roomId);
      // Filed at the deepest place it named, not the room.
      expect(plan.itemLocationIds, {'i1': shelfId});
    });

    test('a room with no container files the item at the room', () {
      final plan = planLocationMigration(
        [itemFixture(id: 'i1', room: 'Kuchnia')],
        const [],
        now,
      );

      final roomId = derivedLocationId(null, 'Kuchnia');

      expect(plan.locations.map((l) => l.name), ['Kuchnia']);
      expect(plan.itemLocationIds, {'i1': roomId});
    });

    test('two items in one place create that place once', () {
      final plan = planLocationMigration(
        [
          itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka'),
          itemFixture(id: 'i2', room: 'Korytarz', container: 'Szafka'),
        ],
        const [],
        now,
      );

      expect(plan.locations.length, 2);
      expect(plan.itemLocationIds.length, 2);
    });

    test('an item with no room is left unfiled', () {
      final plan = planLocationMigration(
        [itemFixture(id: 'i1')],
        const [],
        now,
      );

      expect(plan.isEmpty, isTrue);
    });

    test('an already-filed item is left alone', () {
      final plan = planLocationMigration(
        [itemFixture(id: 'i1', locationId: 'somewhere', room: 'Korytarz')],
        const [],
        now,
      );

      expect(plan.isEmpty, isTrue);
    });

    test('a place that already exists is not created again', () {
      final roomId = derivedLocationId(null, 'Korytarz');
      final existing = Location(
        id: roomId,
        name: 'Korytarz',
        parentId: null,
        sortKey: 0,
        createdAt: now,
        updatedAt: now,
      );

      final plan = planLocationMigration(
        [itemFixture(id: 'i1', room: 'Korytarz')],
        [existing],
        now,
      );

      expect(plan.locations, isEmpty);
      // Still filed, though — the record existing does not mean the item
      // pointing at it does.
      expect(plan.itemLocationIds, {'i1': roomId});
    });

    test('parents come before their children', () {
      final plan = planLocationMigration(
        [
          itemFixture(id: 'i1', room: 'B room', container: 'A shelf'),
        ],
        const [],
        now,
      );

      // Alphabetically the shelf sorts first; ordering by depth is what stops
      // a consumer writing a child whose parent does not exist yet.
      expect(plan.locations.first.parentId, isNull);
      expect(plan.locations.last.parentId, isNotNull);
    });

    test('surrounding whitespace does not create a separate place', () {
      final plan = planLocationMigration(
        [
          itemFixture(id: 'i1', room: 'Korytarz'),
          itemFixture(id: 'i2', room: '  korytarz  '),
        ],
        const [],
        now,
      );

      expect(plan.locations.length, 1);
      expect(
        plan.itemLocationIds.values.toSet().length,
        1,
        reason: 'both items should land in the same room',
      );
    });

    // The property the whole design rests on. Two devices folding the same
    // legacy log independently must produce the *same ids*, because the merge
    // then picks between identical values instead of keeping both — which is
    // the difference between one Korytarz and two after the first sync.
    test('two devices planning the same log agree on every id', () {
      final items = [
        itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka'),
        itemFixture(id: 'i2', room: 'Kuchnia'),
      ];

      final a = planLocationMigration(items, const [], now);
      final b = planLocationMigration(
        items,
        const [],
        // A different clock, as two devices would have.
        now.add(const Duration(hours: 3)),
      );

      expect(
        a.locations.map((l) => l.id).toList(),
        b.locations.map((l) => l.id).toList(),
      );
      expect(a.itemLocationIds, b.itemLocationIds);
    });

    test('re-planning after applying a plan changes nothing', () {
      final items = [
        itemFixture(id: 'i1', room: 'Korytarz', container: 'Szafka'),
      ];
      final first = planLocationMigration(items, const [], now);

      // Apply it: the items now carry ids, the places now exist.
      final migrated = [
        for (final item in items)
          item.copyWith(locationId: first.itemLocationIds[item.id]),
      ];
      final second = planLocationMigration(migrated, first.locations, now);

      expect(second.isEmpty, isTrue);
    });
  });
}
