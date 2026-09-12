import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/barcode_link.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';

import '../support/builders.dart';
import '../support/seeded_persistence.dart';

void main() {
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  group('best-before dates', () {
    final now = DateTime.utc(2026, 7, 26);

    test('a date survives the round trip through the log', () async {
      await repo.upsert(
        itemFixture(id: 'milk', bestBefore: DateTime.utc(2026, 7, 28)),
      );

      expect(repo.item('milk')!.bestBefore, DateTime.utc(2026, 7, 28));
    });

    // An epoch fallback would render every undated screwdriver as expired
    // since 1970, which is why the reader keeps null instead.
    test('no date reads back as null, not as the epoch', () async {
      await repo.upsert(itemFixture(id: 'driver'));

      expect(repo.item('driver')!.bestBefore, isNull);
    });

    test('unparseable stored text reads back as no date', () async {
      await repo.upsert(itemFixture(id: 'odd'));
      final existing = repo.exportLog()['odd']!;
      await repo.replaceAll({
        'odd': Record(
          id: 'odd',
          fields: {
            ...existing.fields,
            'best_before': ('not a date', existing.fields['name']!.$2),
          },
        ),
      });

      expect(repo.item('odd')!.bestBefore, isNull);
    });

    test('listExpiring returns overdue and due-soon, soonest first', () async {
      await repo.upsert(
        itemFixture(
          id: 'gone',
          name: 'Yoghurt',
          bestBefore: DateTime.utc(2026, 7, 20),
        ),
      );
      await repo.upsert(
        itemFixture(
          id: 'soon',
          name: 'Milk',
          bestBefore: DateTime.utc(2026, 7, 28),
        ),
      );
      await repo.upsert(
        itemFixture(id: 'later', name: 'Rice', bestBefore: DateTime.utc(2027)),
      );
      await repo.upsert(itemFixture(id: 'none', name: 'Hammer'));

      final expiring = repo.listExpiring(now: now);

      expect(expiring.map((i) => i.id), ['gone', 'soon']);
    });

    test('listExpiring falls back to the wall clock', () async {
      await repo.upsert(
        itemFixture(id: 'ancient', bestBefore: DateTime.utc(2000)),
      );

      expect(repo.listExpiring().map((i) => i.id), ['ancient']);
    });

    test('watchExpiring re-emits after a write', () async {
      final seen = <List<String>>[];
      final sub = repo
          .watchExpiring(now: now)
          .listen((items) => seen.add(items.map((i) => i.id).toList()));
      await pumpEventQueue();

      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, isEmpty);
      expect(seen.last, ['soon']);
    });

    test('listItems applies the freshness facet as of a given date', () async {
      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await repo.upsert(
        itemFixture(id: 'later', bestBefore: DateTime.utc(2027)),
      );

      final due = repo.listItems(
        filter: const ItemFilter(freshness: {FreshnessState.dueSoon}),
        asOf: now,
      );

      expect(due.map((i) => i.id), ['soon']);
    });

    test('watchItems threads the same clock through', () async {
      await repo.upsert(
        itemFixture(id: 'soon', bestBefore: DateTime.utc(2026, 7, 27)),
      );
      await repo.upsert(itemFixture(id: 'undated'));

      final first = await repo
          .watchItems(
            filter: const ItemFilter(freshness: {FreshnessState.dueSoon}),
            asOf: now,
          )
          .first;

      expect(first.map((i) => i.id), ['soon']);
    });
  });
  group('the expiring-first sort', () {
    List<String> sorted() => repo
        .listItems(sort: ItemSort.expiringFirst)
        .map((i) => i.name)
        .toList();

    test('orders dated items by date and undated ones last', () async {
      await repo.upsert(
        itemFixture(id: 'b', name: 'Bread', bestBefore: DateTime.utc(2026, 8)),
      );
      await repo.upsert(itemFixture(id: 'h', name: 'Hammer'));
      await repo.upsert(
        itemFixture(id: 'm', name: 'Milk', bestBefore: DateTime.utc(2026, 7)),
      );

      expect(sorted(), ['Milk', 'Bread', 'Hammer']);
    });

    test('breaks ties on the same date by name', () async {
      final date = DateTime.utc(2026, 8);
      await repo.upsert(
        itemFixture(id: 'y', name: 'Yoghurt', bestBefore: date),
      );
      await repo.upsert(itemFixture(id: 'k', name: 'Kefir', bestBefore: date));

      expect(sorted(), ['Kefir', 'Yoghurt']);
    });

    test('breaks ties between undated items by name', () async {
      await repo.upsert(itemFixture(id: 's', name: 'Saw'));
      await repo.upsert(itemFixture(id: 'a', name: 'Awl'));

      expect(sorted(), ['Awl', 'Saw']);
    });
  });
}
