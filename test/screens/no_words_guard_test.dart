// Textgate guard: every screen kuhy sees paints no words except his own data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/filter_sheet.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
import 'package:home_inventory/screens/item_form_screen.dart';
import 'package:home_inventory/screens/items_screen.dart';
import 'package:home_inventory/screens/locations_screen.dart';
import 'package:home_inventory/screens/shopping_screen.dart';
import 'package:home_inventory/ui/location_picker.dart';

import '../support/builders.dart';
import '../support/no_words.dart';
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

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, screen);
    await tester.pumpAndSettle();
  }

  /// Pumps a button that opens [open] as a route on top, then taps it.
  Future<void> pumpOpened(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: IconButton(
            key: const Key('open'),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => open(context),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  group('items', () {
    testWidgets('empty list', (tester) async {
      await pump(tester, ItemsScreen(repository: repo, now: () => at));
      expectNoWords(tester);
    });

    testWidgets('search with no matches', (tester) async {
      await repo.upsert(itemFixture(id: 'a', name: 'Flour'));
      await pump(
        tester,
        ItemsScreen(
          repository: repo,
          now: () => at,
          requestedFilter: const ItemFilter(query: 'zzz'),
        ),
      );
      expectNoWords(tester, content: {'zzz'});
    });

    testWidgets('list with badges and summary', (tester) async {
      await repo.upsert(
        itemFixture(id: 'a', name: 'Flour', quantity: 0, lowStockAt: 2),
      );
      await repo.upsert(
        itemFixture(id: 'b', name: 'Rice', quantity: 1, lowStockAt: 2),
      );
      await repo.upsert(
        itemFixture(
          id: 'c',
          name: 'Milk',
          bestBefore: DateTime.utc(2026, 7, 28),
        ),
      );
      await repo.upsert(
        itemFixture(id: 'd', name: 'Eggs', bestBefore: DateTime.utc(2026, 7)),
      );
      await pump(tester, ItemsScreen(repository: repo, now: () => at));
      const names = {'Flour', 'Rice', 'Milk', 'Eggs'};
      expectNoWords(tester, content: names);
      await tester.tap(find.byKey(const Key('items_header_sort')));
      await tester.pumpAndSettle();
      expectNoWords(tester, content: names);
    });

    testWidgets('scan prompt and unknown-code snackbar', (tester) async {
      await pump(tester, ItemsScreen(repository: repo, now: () => at));
      await tester.tap(find.byKey(const Key('items_header_scan')));
      await tester.pumpAndSettle();
      expectNoWords(tester);
      await tester.enterText(
        find.byKey(const Key('code_prompt_barcode')),
        '590123',
      );
      await tester.tap(find.byKey(const Key('code_prompt_ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expectNoWords(tester);
    });

    testWidgets('quick add sheet with an error', (tester) async {
      await pump(tester, ItemsScreen(repository: repo, now: () => at));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expectNoWords(tester);
      await tester.tap(find.byKey(const Key('quick_add_save')));
      await tester.pumpAndSettle();
      expectNoWords(tester);
    });
  });

  testWidgets('shopping, both tabs empty', (tester) async {
    await pump(tester, ShoppingScreen(repository: repo, now: () => at));
    expectNoWords(tester);
    await tester.tap(find.byKey(const Key('tab_to_sell')));
    await tester.pumpAndSettle();
    expectNoWords(tester);
  });

  group('locations', () {
    Widget screen() =>
        LocationsScreen(repository: repo, onSelect: (_) {}, now: () => at);

    testWidgets('empty, then add dialog with an error', (tester) async {
      await pump(tester, screen());
      expectNoWords(tester);
      await tester.tap(find.byKey(const Key('fab_add_place')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_save')));
      await tester.pumpAndSettle();
      expectNoWords(tester);
    });

    testWidgets('a place, its menu and its delete dialog', (tester) async {
      await repo.createLocation(name: 'Kitchen', now: at);
      await pump(tester, screen());
      expectNoWords(tester, content: {'Kitchen'});
      await tester.tap(find.byKey(const Key('menu_more')));
      await tester.pumpAndSettle();
      expectNoWords(tester, content: {'Kitchen'});
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.pumpAndSettle();
      expectNoWords(tester, content: {'Kitchen'});
    });
  });

  testWidgets('item form, edit', (tester) async {
    final item = itemFixture(id: 'a', name: 'Flour', unit: 'kg');
    await repo.upsert(item);
    await pump(
      tester,
      ItemFormScreen(repository: repo, item: item, now: () => at),
    );
    expectNoWords(tester, content: {'Flour', 'kg'});
  });

  testWidgets('item form, new, with errors', (tester) async {
    await pump(tester, ItemFormScreen(repository: repo, now: () => at));
    expectNoWords(tester);
    await tester.tap(find.byKey(const Key('save-button')));
    await tester.pumpAndSettle();
    expectNoWords(tester);
  });

  testWidgets('item detail', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Flour', quantity: 4));
    await repo.adjustQuantity('a', -1, AdjustmentSource.use, now: at);
    await repo.adjustQuantity('a', 1, AdjustmentSource.restock, now: at);
    await repo.linkBarcode(code: '590123', itemId: 'a', unit: 'kg');
    await pump(
      tester,
      ItemDetailScreen(repository: repo, itemId: 'a', now: () => at),
    );
    expectNoWords(tester, content: {'Flour', 'kg'});
  });

  testWidgets('filter sheet', (tester) async {
    await pumpOpened(
      tester,
      (context) => showModalBottomSheet<ItemFilter>(
        context: context,
        builder: (_) =>
            FilterSheet(repository: repo, initial: const ItemFilter()),
      ),
    );
    expectNoWords(tester);
  });

  testWidgets('location picker creating inside a place', (tester) async {
    final kitchen = await repo.createLocation(name: 'Kitchen', now: at);
    await pumpOpened(
      tester,
      (context) => showLocationPicker(
        context,
        repository: repo,
        semanticLabel: 'Pick',
        allowCreate: true,
        createParentId: kitchen.id,
      ),
    );
    expectNoWords(tester, content: {'Kitchen'});
  });

  testWidgets('location picker with no places', (tester) async {
    await pumpOpened(
      tester,
      (context) => showLocationPicker(
        context,
        repository: repo,
        semanticLabel: 'Pick',
        allowCreate: true,
      ),
    );
    expectNoWords(tester);
  });
}
