import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/item_form_screen.dart';
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

  // The form's fields in render order. Indexed rather than looked up by
  // label: a label lives inside the field's InputDecorator, so an
  // ancestor/descendant finder resolves ambiguously once suggestion chips
  // add more Text nodes.
  const name = 0;
  const quantity = 1;
  const unit = 2;
  // The place is a picker, not a text field, so it takes no index here.
  const category = 3;
  const threshold = 4;
  const bestBefore = 5;
  const notes = 6;

  Finder fieldAt(int index) => find.byType(TextFormField).at(index);

  // The form is a lazy ListView taller than the 800x600 default test
  // surface, so its Save button is never *built* — and `ensureVisible` throws
  // "Bad state: No element" on a finder matching nothing, while
  // `scrollUntilVisible` stops as soon as the widget exists, leaving its
  // centre just outside the viewport and the tap missing. Giving the form a
  // surface tall enough to hold it removes the whole class of problem.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await scrollTo(tester, button);
    await tester.tap(button);
  }

  Future<void> toggle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  String textOf(WidgetTester tester, int index) =>
      tester.widget<TextFormField>(fieldAt(index)).controller?.text ?? '';

  /// Opens the place picker and taps the row called [name].
  Future<void> pickPlace(WidgetTester tester, String name) async {
    await scrollTo(tester, find.byType(LocationField));
    await tester.tap(find.byType(LocationField));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  /// `Kitchen › Pantry`, so the form has a tree to pick out of.
  Future<void> seedPlaces() async {
    final kitchen = await repo.createLocation(name: 'Kitchen', now: at);
    await repo.createLocation(name: 'Pantry', parentId: kitchen.id, now: at);
  }

  Future<void> pumpForm(WidgetTester tester, {String? editId}) {
    useTallSurface(tester);
    return pumpApp(
      tester,
      ItemFormScreen(
        repository: repo,
        item: editId == null ? null : repo.item(editId),
        now: () => at,
      ),
    );
  }

  group('creating', () {
    testWidgets('shows the create title and no delete action', (tester) async {
      await pumpForm(tester);

      expect(find.text('New item'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('saves every field', (tester) async {
      await seedPlaces();
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Flour');
      await tester.enterText(fieldAt(quantity), '2.5');
      await tester.enterText(fieldAt(unit), 'kg');
      await pickPlace(tester, 'Pantry');
      await tester.enterText(fieldAt(category), 'Food');
      await scrollTo(tester, fieldAt(threshold));
      await tester.enterText(fieldAt(threshold), '1');
      await scrollTo(tester, fieldAt(notes));
      await tester.enterText(fieldAt(notes), 'wholemeal');
      await toggle(tester, 'I want this');
      await toggle(tester, 'I could sell this');
      await save(tester);
      await tester.pumpAndSettle();

      final item = repo.listItems().single;
      expect(item.name, 'Flour');
      expect(item.quantity, 2.5);
      expect(item.unit, 'kg');
      expect(item.locationId, repo.locationTree().single.children.single.id);
      // The legacy strings keep being written for a device on an older build.
      expect(item.room, 'Kitchen');
      expect(item.container, 'Pantry');
      expect(item.category, 'Food');
      expect(item.lowStockAt, 1);
      expect(item.notes, 'wholemeal');
      expect(item.wanted, isTrue);
      expect(item.sellable, isTrue);
    });

    testWidgets('a blank threshold means never warn', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Thing');
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.listItems().single.lowStockAt, isNull);
    });
  });
  group('validation', () {
    testWidgets('a name is required', (tester) async {
      await pumpForm(tester);

      await save(tester);
      await tester.pump();

      expect(find.text('Give it a name'), findsOneWidget);
      expect(repo.listItems(), isEmpty);
    });

    testWidgets('a quantity is required', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Thing');
      await tester.enterText(fieldAt(quantity), '');
      await save(tester);
      await tester.pump();

      expect(find.text('Enter a number'), findsOneWidget);
    });

    testWidgets('rejects non-numbers and negatives', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Thing');
      await tester.enterText(fieldAt(quantity), 'lots');
      await save(tester);
      await tester.pump();
      expect(find.text('Not a number'), findsOneWidget);

      await tester.enterText(fieldAt(quantity), '-1');
      await save(tester);
      await tester.pump();
      expect(find.text('Cannot be negative'), findsOneWidget);
    });

    testWidgets('validates the threshold too, but allows blank', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Thing');
      await tester.enterText(fieldAt(threshold), 'soon');
      await save(tester);
      await tester.pump();

      expect(find.text('Not a number'), findsOneWidget);
    });
  });
}
