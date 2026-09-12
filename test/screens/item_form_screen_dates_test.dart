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

  group('best before', () {
    testWidgets('a typed date is saved', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Milk');
      await scrollTo(tester, fieldAt(bestBefore));
      await tester.enterText(fieldAt(bestBefore), '2026-08-02');
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.listItems().single.bestBefore, DateTime(2026, 8, 2));
    });

    testWidgets('a blank field means no date at all', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Hammer');
      await save(tester);
      await tester.pumpAndSettle();

      expect(repo.listItems().single.bestBefore, isNull);
    });

    testWidgets('rejects a date in the wrong shape', (tester) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Milk');
      await scrollTo(tester, fieldAt(bestBefore));
      await tester.enterText(fieldAt(bestBefore), '02/08/2026');
      await save(tester);
      await tester.pump();

      expect(find.text('Use YYYY-MM-DD'), findsOneWidget);
      expect(repo.listItems(), isEmpty);
    });

    // DateTime.parse rolls this over to 2027-02-14 rather than failing, so
    // without the round-trip check the form would store a date nobody typed.
    testWidgets('rejects an impossible date rather than rolling it over', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(fieldAt(name), 'Milk');
      await scrollTo(tester, fieldAt(bestBefore));
      await tester.enterText(fieldAt(bestBefore), '2026-13-45');
      await save(tester);
      await tester.pump();

      expect(find.text('Not a real date'), findsOneWidget);
      expect(repo.listItems(), isEmpty);
    });

    testWidgets('editing prefills the stored date', (tester) async {
      await repo.upsert(
        itemFixture(id: 'dated', bestBefore: DateTime(2026, 8, 9)),
      );
      await pumpForm(tester, editId: 'dated');

      expect(textOf(tester, bestBefore), '2026-08-09');
    });

    testWidgets('the calendar writes the chosen day into the field', (
      tester,
    ) async {
      await pumpForm(tester);

      await scrollTo(tester, find.byIcon(Icons.calendar_today_outlined));
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(textOf(tester, bestBefore), '2026-07-30');
    });

    testWidgets('a cancelled calendar leaves the field alone', (tester) async {
      await repo.upsert(
        itemFixture(id: 'dated', bestBefore: DateTime(2026, 8, 9)),
      );
      await pumpForm(tester, editId: 'dated');

      await scrollTo(tester, find.byIcon(Icons.calendar_today_outlined));
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(textOf(tester, bestBefore), '2026-08-09');
    });
  });
}
