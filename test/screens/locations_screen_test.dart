import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/locations_screen.dart';

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

  /// Records what the screen asked the shell to show.
  final selections = <(String, String?)>[];

  setUp(selections.clear);

  Future<void> pumpLocations(WidgetTester tester) async {
    await pumpApp(
      tester,
      LocationsScreen(
        repository: repo,
        onSelect: (room, container) => selections.add((room, container)),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the empty state with nothing filed', (tester) async {
    await pumpLocations(tester);

    expect(find.text('No locations yet'), findsOneWidget);
  });

  testWidgets('lists rooms with their item counts', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    await repo.upsert(itemFixture(id: 'b', room: 'Office'));
    await repo.upsert(itemFixture(id: 'c', room: 'Kitchen'));

    await pumpLocations(tester);

    expect(find.text('Office'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  // An item with no room still has to be reachable, or it is invisible on the
  // one screen whose whole job is finding things.
  testWidgets('an unfiled item appears under "No room"', (tester) async {
    await repo.upsert(itemFixture(id: 'a'));

    await pumpLocations(tester);

    expect(find.text('No room'), findsOneWidget);
  });

  testWidgets('expanding a room reveals its containers', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', room: 'Office', container: 'Drawer 2'),
    );
    await pumpLocations(tester);

    expect(find.text('Drawer 2'), findsNothing);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer 2'), findsOneWidget);
  });

  testWidgets('an item with no container reads as loose in the room', (
    tester,
  ) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Loose in the room'), findsOneWidget);
  });

  testWidgets('the arrow selects the whole room', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Office'));
    await pumpLocations(tester);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();

    expect(selections, [('Office', null)]);
  });

  testWidgets('a container row selects that container', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', room: 'Office', container: 'Drawer 2'),
    );
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drawer 2'));
    await tester.pump();

    expect(selections, [('Office', 'Drawer 2')]);
  });
}
