import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/item_form_screen.dart';

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
  const room = 3;
  const container = 4;
  const category = 5;
  const threshold = 6;
  const notes = 7;

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
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Flour');
      await tester.enterText(fieldAt(quantity), '2.5');
      await tester.enterText(
        fieldAt(unit),
        'kg',
      );
      await tester.enterText(fieldAt(room), 'Kitchen');
      await tester.enterText(fieldAt(container), 'Pantry');
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
      await tester.enterText(
        fieldAt(threshold),
        'soon',
      );
      await save(tester);
      await tester.pump();

      expect(find.text('Not a number'), findsOneWidget);
    });
  });

  group('editing', () {
    setUp(() async {
      await repo.upsert(
        itemFixture(
          id: 'i1',
          name: 'Flour',
          quantity: 5,
          unit: 'kg',
          room: 'Kitchen',
          lowStockAt: 2,
          wanted: true,
          sellable: true,
          notes: 'note',
          updatedAt: at,
        ),
      );
    });

    testWidgets('pre-fills from the existing item', (tester) async {
      await pumpForm(tester, editId: 'i1');

      expect(find.text('Edit item'), findsOneWidget);
      expect(textOf(tester, name), 'Flour');
      expect(textOf(tester, quantity), '5');
      expect(textOf(tester, unit), 'kg');
      expect(textOf(tester, room), 'Kitchen');
      expect(textOf(tester, threshold), '2');
      expect(textOf(tester, notes), 'note');
    });

    testWidgets('keeps the original id and creation date', (tester) async {
      final before = repo.item('i1')!;
      await pumpForm(tester, editId: 'i1');

      await tester.enterText(fieldAt(name), 'Bread flour');
      await save(tester);
      await tester.pumpAndSettle();

      final after = repo.item('i1')!;
      expect(after.name, 'Bread flour');
      expect(after.id, before.id);
      expect(after.createdAt, before.createdAt);
    });

    // A number typed into this form is a recount. Reading it as consumption
    // is the one mistake that silently corrupts the rate projection.
    testWidgets('a quantity typed here is a correction, never use', (
      tester,
    ) async {
      await pumpForm(tester, editId: 'i1');

      await tester.enterText(fieldAt(quantity), '3');
      await save(tester);
      await tester.pumpAndSettle();

      expect(
        repo.historyFor('i1').last.source,
        AdjustmentSource.correction,
      );
    });

    testWidgets('can clear the threshold by blanking it', (tester) async {
      await pumpForm(tester, editId: 'i1');

      await scrollTo(tester, fieldAt(threshold));
      await tester.enterText(fieldAt(threshold), '');
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.item('i1')!.lowStockAt, isNull);
    });

    testWidgets('deletes the item', (tester) async {
      await pumpForm(tester, editId: 'i1');

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(repo.item('i1'), isNull);
    });

    testWidgets('can turn the flags back off', (tester) async {
      await pumpForm(tester, editId: 'i1');

      await toggle(tester, 'I want this');
      await toggle(tester, 'I could sell this');
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.item('i1')!.wanted, isFalse);
      expect(repo.item('i1')!.sellable, isFalse);
    });
  });
}
