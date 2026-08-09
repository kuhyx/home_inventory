import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
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

  testWidgets('offers the stock states and flags with an empty store', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Wanted'), findsOneWidget);
  });

  // An empty group is worse than no group: a "Categories" heading over blank
  // space reads as a loading failure rather than "you have not used any".
  testWidgets('hides groups that have nothing to offer', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Categories'), findsNothing);
  });

  testWidgets('stock and flag chips are selectable too', (tester) async {
    final popped = await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Out'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Sellable'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(
      popped.single,
      const ItemFilter(
        stock: {StockState.out},
        flags: {ItemFlag.sellable},
      ),
    );
  });

  group('the place facet', () {
    testWidgets('reads "Anywhere" when nothing is picked', (tester) async {
      await pumpSheet(tester);

      expect(find.text('Anywhere'), findsOneWidget);
    });

    // A tree cannot be a chip row: chips could not say which cupboard a shelf
    // belongs to, and every shelf in the flat side by side is unusable.
    testWidgets('picking a place selects its whole subtree', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: at);
      final drawer = await repo.createLocation(
        name: 'Drawer 2',
        parentId: office.id,
        now: at,
      );
      final popped = await pumpSheet(tester);

      await tester.tap(find.text('Anywhere'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Office').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.locationIds, {office.id, drawer.id});
    });

    testWidgets('shows the chosen place', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: at);
      await pumpSheet(
        tester,
        initial: ItemFilter(locationIds: {office.id}),
      );

      expect(find.text('Office'), findsOneWidget);
    });

    testWidgets('clearing it goes back to anywhere', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: at);
      final popped = await pumpSheet(
        tester,
        initial: ItemFilter(locationIds: {office.id}),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.locationIds, isEmpty);
    });

    testWidgets('choosing "Anywhere" in the picker clears it', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: at);
      final popped = await pumpSheet(
        tester,
        initial: ItemFilter(locationIds: {office.id}),
      );

      await tester.tap(find.text('Office'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anywhere').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.locationIds, isEmpty);
    });

    testWidgets('dismissing the picker changes nothing', (tester) async {
      await repo.createLocation(name: 'Office', now: at);
      final popped = await pumpSheet(tester);

      await tester.tap(find.text('Anywhere'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(popped.single!.locationIds, isEmpty);
    });

    testWidgets('says so when there are no places yet', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Anywhere'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No places yet'), findsOneWidget);
    });
  });

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

  // The search box stays visibly full, so wiping the query from here would
  // look like the app lost what was typed.
  testWidgets('Clear all drops the facets but keeps the query', (
    tester,
  ) async {
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
}
