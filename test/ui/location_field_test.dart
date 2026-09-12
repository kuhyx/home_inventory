import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/ui/location_field.dart';

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

  /// Renders the field over a scaffold, recording every id it reports.
  Future<List<String>> pumpField(
    WidgetTester tester, {
    String locationId = '',
    String fallbackLabel = '',
  }) async {
    final changes = <String>[];
    var current = locationId;
    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: LocationField(
            repository: repo,
            locationId: current,
            fallbackLabel: fallbackLabel,
            now: () => now,
            onChanged: (id) => setState(() {
              changes.add(id);
              current = id;
            }),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('says so when nothing is filed', (tester) async {
    await pumpField(tester);

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Not filed anywhere'), findsOneWidget);
  });

  testWidgets('shows the whole path, not just the leaf', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: now);
    final shelf = await repo.createLocation(
      name: 'szafka z lewej',
      parentId: room.id,
      now: now,
    );

    await pumpField(tester, locationId: shelf.id);

    expect(find.text('korytarz › szafka z lewej'), findsOneWidget);
  });

  // An item the places migration has not reached yet still knows where it is,
  // as two strings. Showing "nowhere" would read as the app having lost it.
  testWidgets('falls back to the legacy strings', (tester) async {
    await pumpField(tester, fallbackLabel: 'Shed › Crate');

    expect(find.text('Shed › Crate'), findsOneWidget);
  });

  testWidgets('a place that is gone reads as unfiled', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: now);
    await repo.deleteLocation(room.id);

    await pumpField(tester, locationId: room.id);

    expect(find.text('Not filed anywhere'), findsOneWidget);
  });

  testWidgets('reports the place picked from the tree', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: now);
    final changes = await pumpField(tester);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('korytarz').last);
    await tester.pumpAndSettle();

    expect(changes, [room.id]);
    expect(find.text('korytarz'), findsOneWidget);
  });

  testWidgets('reports the explicit "nowhere"', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: now);
    final changes = await pumpField(tester, locationId: room.id);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not filed anywhere').last);
    await tester.pumpAndSettle();

    expect(changes, ['']);
  });

  testWidgets('a dismissed picker changes nothing', (tester) async {
    await repo.createLocation(name: 'korytarz', now: now);
    final changes = await pumpField(tester);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  testWidgets('announces a room it had to create', (tester) async {
    final changes = await pumpField(tester);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'korytarz');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Created "korytarz" as a new room'), findsOneWidget);
    expect(changes.single, repo.listLocations().single.id);
  });

  // Q2: a typed name lands inside whatever is selected, so adding a shelf to
  // the cupboard you just picked never means a trip to the Locations tab.
  testWidgets('announces where a nested place landed', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: now);
    await pumpField(tester, locationId: room.id);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'szafka z lewej');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Created "szafka z lewej" in korytarz'), findsOneWidget);
    expect(find.text('korytarz › szafka z lewej'), findsOneWidget);
  });

  testWidgets('says nothing when the typed name already existed', (
    tester,
  ) async {
    await repo.createLocation(name: 'korytarz', now: now);
    await pumpField(tester);

    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Korytarz');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.textContaining('Created'), findsNothing);
    expect(repo.listLocations(), hasLength(1));
  });
}
