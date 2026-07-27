import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/quick_add_sheet.dart';

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

  Future<void> pumpSheet(WidgetTester tester) => pumpApp(
    tester,
    Scaffold(
      body: QuickAddSheet(repository: repo, now: () => at),
    ),
  );

  // The done condition runs straight through this test: name, where, how
  // many, save.
  testWidgets('saves an item with its name, quantity and location', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'USB-C cable');
    await tester.enterText(find.byType(TextFormField).at(1), '4');
    await tester.enterText(find.byType(TextFormField).at(2), 'Office');
    await tester.enterText(find.byType(TextFormField).at(3), 'Desk drawer 2');
    await tester.tap(find.text('Save'));
    await tester.pump();

    final item = repo.listItems().single;
    expect(item.name, 'USB-C cable');
    expect(item.quantity, 4);
    expect(item.room, 'Office');
    expect(item.container, 'Desk drawer 2');
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

    await tester.enterText(find.byType(TextFormField).at(0), 'First');
    await tester.enterText(find.byType(TextFormField).at(2), 'Shed');
    await tester.tap(find.text('Save & add another'));
    await tester.pump();

    expect(repo.listItems(), hasLength(1));
    final name = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    expect(name.controller?.text, isEmpty);
    final room = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
    );
    expect(room.controller?.text, 'Shed');
  });

  testWidgets('Save & add another does not save an invalid item', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Save & add another'));
    await tester.pump();

    expect(repo.listItems(), isEmpty);
  });

  testWidgets('pre-fills the most-used room', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Kitchen'));
    await repo.upsert(itemFixture(id: 'b', room: 'Kitchen'));
    await repo.upsert(itemFixture(id: 'c', room: 'Shed'));

    await pumpSheet(tester);

    final room = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
    );
    expect(room.controller?.text, 'Kitchen');
  });

  testWidgets('leaves the room blank when there is no history', (
    tester,
  ) async {
    await pumpSheet(tester);

    final room = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
    );
    expect(room.controller?.text, isEmpty);
  });

  testWidgets('offers known rooms as tappable chips', (tester) async {
    await repo.upsert(itemFixture(id: 'a', room: 'Kitchen'));
    await repo.upsert(itemFixture(id: 'b', room: 'Shed'));

    await pumpSheet(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Shed'));
    await tester.pump();

    final room = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
    );
    expect(room.controller?.text, 'Shed');
  });
}
