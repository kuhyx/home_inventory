import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/quick_add_sheet.dart';
import 'package:home_inventory/ui/location_field.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
  final at = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  Future<void> pumpSheet(WidgetTester tester, {String? initialLocationId}) =>
      pumpApp(
        tester,
        Scaffold(
          body: QuickAddSheet(
            repository: repo,
            initialLocationId: initialLocationId,
            now: () => at,
          ),
        ),
      );

  /// Opens the place picker and taps the row called [name].
  Future<void> pickPlace(WidgetTester tester, String name) async {
    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  /// `Kitchen › Pantry`, plus the id of the shelf.
  Future<String> seedPlaces() async {
    final kitchen = await repo.createLocation(name: 'Kitchen', now: at);
    final pantry = await repo.createLocation(
      name: 'Pantry',
      parentId: kitchen.id,
      now: at,
    );
    return pantry.id;
  }

  // The done condition runs straight through this test: name, where, how
  // many, save.
  testWidgets('pre-fills the place the list is filtered to', (tester) async {
    final pantry = await seedPlaces();
    await pumpSheet(tester, initialLocationId: pantry);

    expect(find.text('Kitchen › Pantry'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Rice');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(repo.listItems().single.locationId, pantry);
  });
  testWidgets('falls back to the busiest place when nothing is filtered', (
    tester,
  ) async {
    final pantry = await seedPlaces();
    final kitchen = repo.locationTree().single.id;
    await repo.upsert(itemFixture(id: 'a', locationId: kitchen));
    await repo.upsert(itemFixture(id: 'b', locationId: kitchen));
    await repo.upsert(itemFixture(id: 'c', locationId: pantry));

    await pumpSheet(tester);

    expect(find.text('Kitchen'), findsOneWidget);
  });
  testWidgets('leaves the place empty when nothing is filed yet', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Not filed anywhere'), findsOneWidget);
  });
  testWidgets('creates a place typed into the picker, and says so', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Broom');
    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'korytarz');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Created "korytarz" as a new room'), findsOneWidget);
    expect(find.text('korytarz'), findsWidgets);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final item = repo.listItems().single;
    expect(repo.pathLabel(item.locationId), 'korytarz');
    expect(item.room, 'korytarz');
  });
  testWidgets('a typed place is created inside the selected one', (
    tester,
  ) async {
    await repo.createLocation(name: 'korytarz', now: at);
    await pumpSheet(tester);

    await pickPlace(tester, 'korytarz');
    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    expect(find.text('New place in korytarz'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'szafka z lewej');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Created "szafka z lewej" in korytarz'), findsOneWidget);
    expect(find.text('korytarz › szafka z lewej'), findsOneWidget);
  });
  testWidgets('typing an existing name just picks it', (tester) async {
    await repo.createLocation(name: 'korytarz', now: at);
    await pumpSheet(tester);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Korytarz');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.textContaining('Created'), findsNothing);
    expect(repo.listLocations(), hasLength(1));
    expect(find.text('korytarz'), findsOneWidget);
  });
}
