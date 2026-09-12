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
      // No place record yet — the legacy string is what it still knows.
      expect(find.text('Kitchen'), findsOneWidget);
      expect(textOf(tester, threshold), '2');
      expect(textOf(tester, notes), 'note');
    });

    // Q4: an item that predates the places tree gets filed for real on the
    // next save, at the same derived id `planLocationMigration` would pick.
    testWidgets('files a legacy room/container item on save', (tester) async {
      await repo.upsert(
        itemFixture(id: 'i2', name: 'Tape', room: 'Shed', container: 'Crate'),
      );
      await pumpForm(tester, editId: 'i2');

      await save(tester);
      await tester.pumpAndSettle();

      final item = repo.item('i2')!;
      expect(repo.pathLabel(item.locationId), 'Shed › Crate');
      expect(item.room, 'Shed');
      expect(item.container, 'Crate');
    });

    testWidgets('an explicit "nowhere" wins over the legacy strings', (
      tester,
    ) async {
      await repo.upsert(itemFixture(id: 'i3', name: 'Tape', room: 'Shed'));
      await pumpForm(tester, editId: 'i3');

      await scrollTo(tester, find.byType(LocationField));
      await tester.tap(find.byType(LocationField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not filed anywhere').last);
      await tester.pumpAndSettle();
      await save(tester);
      await tester.pumpAndSettle();

      final item = repo.item('i3')!;
      expect(item.locationId, isEmpty);
      expect(item.room, isEmpty);
      expect(repo.listLocations(), isEmpty);
    });

    testWidgets('keeps the place when it is already filed', (tester) async {
      await seedPlaces();
      final pantry = repo.locationTree().single.children.single.id;
      await repo.upsert(
        itemFixture(id: 'i4', name: 'Rice', locationId: pantry),
      );
      await pumpForm(tester, editId: 'i4');

      expect(find.text('Kitchen › Pantry'), findsOneWidget);
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.item('i4')!.locationId, pantry);
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

      expect(repo.historyFor('i1').last.source, AdjustmentSource.correction);
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
