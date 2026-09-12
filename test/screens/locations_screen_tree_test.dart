import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/locations_screen.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  /// Which place the screen asked the shell to show.
  final selections = <String>[];

  setUp(selections.clear);

  Future<void> pumpLocations(WidgetTester tester) async {
    await pumpApp(
      tester,
      LocationsScreen(
        repository: repo,
        onSelect: selections.add,
        now: () => now,
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the empty state with nothing filed', (tester) async {
    await pumpLocations(tester);

    expect(find.text('No locations yet'), findsOneWidget);
  });
  testWidgets('lists places with their item counts', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    final kitchen = await repo.createLocation(name: 'Kitchen', now: now);
    await repo.upsert(itemFixture(id: 'a', locationId: office.id));
    await repo.upsert(itemFixture(id: 'b', locationId: office.id));
    await repo.upsert(itemFixture(id: 'c', locationId: kitchen.id));

    await pumpLocations(tester);

    expect(find.text('Office'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });
  testWidgets('a place with no items still shows', (tester) async {
    await repo.createLocation(name: 'Garaż', now: now);

    await pumpLocations(tester);

    expect(find.text('Garaż'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);
  });
  testWidgets('children stay hidden until the parent is expanded', (
    tester,
  ) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await repo.createLocation(name: 'Drawer 2', parentId: office.id, now: now);
    await pumpLocations(tester);

    expect(find.text('Drawer 2'), findsNothing);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer 2'), findsOneWidget);
  });
  testWidgets('collapsing hides them again', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await repo.createLocation(name: 'Drawer 2', parentId: office.id, now: now);
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer 2'), findsNothing);
  });
  testWidgets('nests as deep as the user likes', (tester) async {
    final l1 = await repo.createLocation(name: 'korytarz', now: now);
    final l2 = await repo.createLocation(
      name: 'szafka z lewej',
      parentId: l1.id,
      now: now,
    );
    final l3 = await repo.createLocation(
      name: 'najwyższa półka',
      parentId: l2.id,
      now: now,
    );
    await repo.createLocation(
      name: 'sekcja przy drzwiach',
      parentId: l3.id,
      now: now,
    );
    await pumpLocations(tester);

    for (final name in ['korytarz', 'szafka z lewej', 'najwyższa półka']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    expect(find.text('sekcja przy drzwiach'), findsOneWidget);
  });
  testWidgets('the arrow selects the place', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await pumpLocations(tester);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();

    expect(selections, [office.id]);
  });
  testWidgets('tapping a childless row selects it', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pump();

    expect(selections, [office.id]);
  });
}
