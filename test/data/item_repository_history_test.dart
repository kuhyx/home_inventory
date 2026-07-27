import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';

import '../support/builders.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  /// Seeds an item plus [count] `use` decrements spread evenly back over
  /// [spanDays], each removing [each].
  Future<void> seedUses({
    required int count,
    required double spanDays,
    double each = 1,
    double startQuantity = 40,
    double? lowStockAt,
    AdjustmentSource source = AdjustmentSource.use,
  }) async {
    await repo.upsert(
      itemFixture(
        quantity: startQuantity,
        lowStockAt: lowStockAt,
        updatedAt: now,
      ),
    );
    for (var i = 0; i < count; i++) {
      final age = spanDays - (i * spanDays / (count == 1 ? 1 : count - 1));
      await repo.adjustQuantity(
        'i1',
        -each,
        source,
        now: now.subtract(Duration(minutes: (age * 24 * 60).round())),
      );
    }
  }

  group('historyFor', () {
    test('is empty for an item with no changes', () {
      expect(repo.historyFor('i1'), isEmpty);
    });

    test('returns changes oldest first', () async {
      await repo.upsert(itemFixture(quantity: 10, updatedAt: now));
      await repo.adjustQuantity(
        'i1',
        -1,
        AdjustmentSource.use,
        now: now.subtract(const Duration(days: 1)),
      );
      await repo.adjustQuantity(
        'i1',
        -2,
        AdjustmentSource.use,
        now: now.subtract(const Duration(days: 5)),
      );

      // The opening +10 is stamped with the item's own updatedAt (now), so
      // oldest-first puts the two backdated uses ahead of it.
      final deltas = repo.historyFor('i1').map((a) => a.delta).toList();
      expect(deltas, [-2, -1, 10]);
    });

    test('is unmodifiable', () async {
      await repo.upsert(itemFixture(quantity: 1, updatedAt: now));

      expect(
        () => repo.historyFor('i1').add(repo.historyFor('i1').first),
        throwsUnsupportedError,
      );
    });

    test('keeps each item separate', () async {
      await repo.upsert(itemFixture(id: 'a', quantity: 2, updatedAt: now));
      await repo.upsert(itemFixture(id: 'b', quantity: 3, updatedAt: now));

      expect(repo.historyFor('a'), hasLength(1));
      expect(repo.historyFor('b'), hasLength(1));
    });
  });

  group('rateHint — the happy path', () {
    test('projects days until the threshold, not until zero', () async {
      // 20 uses of 1 over 40 days = 0.5/day, and those uses really do drain
      // the stock: 40 - 20 = 20 left. Against a threshold of 10 that is 10
      // of headroom, so ~20 days — not 60, which is what projecting to zero
      // from the opening quantity would give.
      await seedUses(count: 20, spanDays: 40, lowStockAt: 10);

      final hint = repo.rateHint('i1', now: now)!;

      expect(hint.sampleCount, 20);
      expect(hint.perDay, closeTo(0.5, 0.05));
      expect(hint.daysLeft, closeTo(20, 3));
    });

    test('treats a missing threshold as zero', () async {
      await seedUses(count: 20, spanDays: 40);

      final hint = repo.rateHint('i1', now: now)!;

      // 20 left, all of it headroom, at ~0.5/day.
      expect(hint.daysLeft, closeTo(40, 4));
    });
  });

  // Production never passes `now`; every other test does, so without this
  // the default-clock path ships unexercised.
  test('defaults to the wall clock when no time is given', () async {
    final today = DateTime.now();
    await repo.upsert(itemFixture(quantity: 40, updatedAt: today));
    for (var i = 0; i < 20; i++) {
      await repo.adjustQuantity(
        'i1',
        -1,
        AdjustmentSource.use,
        now: today.subtract(Duration(days: 40 - (i * 2))),
      );
    }

    expect(repo.rateHint('i1'), isNotNull);
  });

  group('rateHint — every reason to stay quiet', () {
    test('unknown item', () {
      expect(repo.rateHint('nope', now: now), isNull);
    });

    test('an item with no history at all', () async {
      await repo.upsert(itemFixture(quantity: 0));

      expect(repo.rateHint('i1', now: now), isNull);
    });

    test('too few samples', () async {
      await seedUses(count: 2, spanDays: 40);

      expect(repo.rateHint('i1', now: now), isNull);
    });

    // Three uses in one afternoon says nothing about a weekly rate.
    test('span too short', () async {
      await seedUses(count: 5, spanDays: 3);

      expect(repo.rateHint('i1', now: now), isNull);
    });

    test('restocks and corrections do not count as usage', () async {
      await seedUses(
        count: 8,
        spanDays: 40,
        source: AdjustmentSource.correction,
      );

      expect(repo.rateHint('i1', now: now), isNull);
    });

    test('already at or below the threshold', () async {
      await seedUses(
        count: 20,
        spanDays: 40,
        startQuantity: 5,
        lowStockAt: 10,
      );

      expect(repo.rateHint('i1', now: now), isNull);
    });

    // A trickle against a huge stock projects years out; that is noise, not
    // information.
    test('projection beyond a year', () async {
      await seedUses(
        count: 3,
        spanDays: 80,
        each: 0.01,
        startQuantity: 500,
      );

      expect(repo.rateHint('i1', now: now), isNull);
    });

    test('usage older than the window is ignored', () async {
      await repo.upsert(itemFixture(quantity: 40, updatedAt: now));
      for (var i = 0; i < 6; i++) {
        await repo.adjustQuantity(
          'i1',
          -1,
          AdjustmentSource.use,
          now: now.subtract(Duration(days: 200 + i)),
        );
      }

      expect(repo.rateHint('i1', now: now), isNull);
    });

    // A device with a clock set into the future would otherwise produce a
    // negative span and a nonsense projection.
    test('future-dated usage is discarded', () async {
      await repo.upsert(itemFixture(quantity: 40, updatedAt: now));
      for (var i = 0; i < 6; i++) {
        await repo.adjustQuantity(
          'i1',
          -1,
          AdjustmentSource.use,
          now: now.add(Duration(days: 10 + i)),
        );
      }

      expect(repo.rateHint('i1', now: now), isNull);
    });
  });

  // The projection window must stay strictly inside the retention horizon,
  // or pruning could delete a record the projection was about to use.
  test('retention never removes a record the rate window needs', () async {
    await seedUses(count: 20, spanDays: 40, lowStockAt: 10);
    final before = repo.rateHint('i1', now: now);

    await repo.pruneHistory(now: now);

    expect(repo.rateHint('i1', now: now)!.sampleCount, before!.sampleCount);
  });
}
