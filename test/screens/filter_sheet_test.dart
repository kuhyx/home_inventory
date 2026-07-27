import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/filter_sheet.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
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

  testWidgets('sources its room chips from the inventory', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));

    await pumpSheet(tester);

    expect(find.widgetWithText(FilterChip, 'Office'), findsOneWidget);
  });

  testWidgets('applying pops the edited filter', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    final popped = await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Office'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter(rooms: {'Office'}));
  });

  testWidgets('tapping a selected chip deselects it', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    final popped = await pumpSheet(
      tester,
      initial: const ItemFilter(rooms: {'Office'}),
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Office'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter());
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

  testWidgets('containers narrow to the selected rooms', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', room: 'Office', container: 'Drawer 2'),
    );
    await repo.upsert(
      itemFixture(id: 'b', room: 'Kitchen', container: 'Top shelf'),
    );

    await pumpSheet(tester, initial: const ItemFilter(rooms: {'Office'}));

    expect(find.widgetWithText(FilterChip, 'Drawer 2'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Top shelf'), findsNothing);
  });

  testWidgets('every container is offered while no room is picked', (
    tester,
  ) async {
    await repo.upsert(
      itemFixture(id: 'a', room: 'Office', container: 'Drawer 2'),
    );
    await repo.upsert(
      itemFixture(id: 'b', room: 'Kitchen', container: 'Top shelf'),
    );

    await pumpSheet(tester);

    expect(find.widgetWithText(FilterChip, 'Drawer 2'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Top shelf'), findsOneWidget);
  });

  testWidgets('a container chip is selectable', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', room: 'Office', container: 'Drawer 2'),
    );
    final popped = await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Drawer 2'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(popped.single, const ItemFilter(containers: {'Drawer 2'}));
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
      initial: const ItemFilter(query: 'cable', rooms: {'Office'}),
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
