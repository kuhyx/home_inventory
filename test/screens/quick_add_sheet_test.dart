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
  testWidgets('saves an item with its name, quantity and location', (
    tester,
  ) async {
    final pantry = await seedPlaces();
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'USB-C cable');
    await tester.enterText(find.byType(TextFormField).at(1), '4');
    await pickPlace(tester, 'Pantry');
    await tester.tap(find.text('Save'));
    await tester.pump();

    final item = repo.listItems().single;
    expect(item.name, 'USB-C cable');
    expect(item.quantity, 4);
    expect(item.locationId, pantry);
    // Legacy strings alongside the id, for a device on an older build.
    expect(item.room, 'Kitchen');
    expect(item.container, 'Pantry');
    expect(item.createdAt, at);
  });

  testWidgets('the opening quantity is recorded as initial, not use', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Flour');
    await tester.tap(find.text('Save'));
    await tester.pump();

    final item = repo.listItems().single;
    expect(repo.historyFor(item.id).single.source, AdjustmentSource.initial);
  });

  testWidgets('refuses to save without a name', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Give it a name'), findsOneWidget);
    expect(repo.listItems(), isEmpty);
  });

  testWidgets('rejects a quantity that is not a number', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Thing');
    await tester.enterText(find.byType(TextFormField).at(1), 'lots');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Quantity must be a number'), findsOneWidget);
    expect(repo.listItems(), isEmpty);
  });

  testWidgets('rejects a negative quantity', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Thing');
    await tester.enterText(find.byType(TextFormField).at(1), '-2');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Quantity must be a number'), findsOneWidget);
  });

  testWidgets('a blank quantity means one', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Thing');
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(repo.listItems().single.quantity, 1);
  });

  testWidgets('accepts a comma decimal separator', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Flour');
    await tester.enterText(find.byType(TextFormField).at(1), '2,5');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(repo.listItems().single.quantity, 2.5);
  });

  // Consecutive adds are nearly always in the same place, so keeping the
  // location is what makes bulk entry fast.
  testWidgets('Save & add another keeps the location but clears the name', (
    tester,
  ) async {
    await pumpSheet(tester);

    await seedPlaces();
    await tester.enterText(find.byType(TextFormField).at(0), 'First');
    await pickPlace(tester, 'Pantry');
    await tester.tap(find.text('Save & add another'));
    await tester.pumpAndSettle();

    expect(repo.listItems(), hasLength(1));
    final name = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    expect(name.controller?.text, isEmpty);
    expect(find.text('Kitchen › Pantry'), findsOneWidget);
  });

  testWidgets('Save & add another does not save an invalid item', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Save & add another'));
    await tester.pump();

    expect(repo.listItems(), isEmpty);
  });

  // Point 2: standing in the hallway with the list filtered to it, the next
  // thing added is in the hallway.
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

  // Point 1: a name that is not a place yet becomes one, and says so.
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

  // Q2: a typed name lands inside whatever is already selected.
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

    expect(
      find.text('Created "szafka z lewej" in korytarz'),
      findsOneWidget,
    );
    expect(find.text('korytarz › szafka z lewej'), findsOneWidget);
  });

  // An existing place typed by name is selected, not announced as new — and
  // the fold means the casing does not matter.
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
