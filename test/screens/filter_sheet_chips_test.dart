import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/filter_sheet.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
  final at = DateTime.utc(2026, 8, 5);
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  /// Pumps the sheet in a route, and records whatever it pops with.
  ///
  /// The surface is enlarged first: the default 800x600 test view is shorter
  /// than the sheet once it has more than a couple of chip groups, and a tap
  /// on a widget pushed below the fold silently misses rather than failing.
  Future<List<ItemFilter?>> pumpSheet(
    WidgetTester tester, {
    ItemFilter initial = const ItemFilter(),
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final popped = <ItemFilter?>[];
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              popped.add(
                await showModalBottomSheet<ItemFilter>(
                  context: context,
                  builder: (_) =>
                      FilterSheet(repository: repo, initial: initial),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('tapping a selected chip deselects it', (tester) async {
    await repo.upsert(itemFixture(id: 'a', category: 'Tools'));
    final popped = await pumpSheet(
      tester,
      initial: const ItemFilter(categories: {'Tools'}),
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Tools'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter());
  });
  testWidgets('a category chip is selectable', (tester) async {
    await repo.upsert(itemFixture(id: 'a', category: 'Tools'));
    final popped = await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Tools'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter(categories: {'Tools'}));
  });
  testWidgets('Clear all drops the facets but keeps the query', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    final popped = await pumpSheet(
      tester,
      initial: const ItemFilter(query: 'cable', locationIds: {'loc1'}),
    );

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter(query: 'cable'));
  });
  testWidgets('dismissing pops null rather than an empty filter', (
    tester,
  ) async {
    final popped = await pumpSheet(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(popped.single, isNull);
  });
  group('the best-before group', () {
    testWidgets('offers every freshness state', (tester) async {
      await pumpSheet(tester);

      expect(find.text('Best before'), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Due soon'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('selecting one applies it', (tester) async {
      final popped = await pumpSheet(tester);

      await tester.tap(find.text('Due soon'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.freshness, {FreshnessState.dueSoon});
    });

    testWidgets('tapping a selected one clears it again', (tester) async {
      final popped = await pumpSheet(
        tester,
        initial: const ItemFilter(freshness: {FreshnessState.expired}),
      );

      await tester.tap(find.text('Expired'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.freshness, isEmpty);
    });
  });
}
