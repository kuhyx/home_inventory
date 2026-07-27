import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/shopping_screen.dart';

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

  Future<void> pumpShopping(WidgetTester tester) async {
    await pumpApp(tester, ShoppingScreen(repository: repo, now: () => at));
    await tester.pump();
  }

  Future<void> openSellTab(WidgetTester tester) async {
    await tester.tap(find.text('To sell'));
    await tester.pumpAndSettle();
  }

  testWidgets('says so when there is nothing to buy', (tester) async {
    await repo.upsert(itemFixture(id: 'a', quantity: 5));

    await pumpShopping(tester);

    expect(find.text('Nothing to buy'), findsOneWidget);
  });

  testWidgets('lists items that are out of stock', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Flour', quantity: 0));

    await pumpShopping(tester);

    expect(find.text('Flour'), findsOneWidget);
  });

  // The union is the whole point: a wanted item that is fully stocked would
  // vanish under an AND of "low or out" with "wanted".
  testWidgets('lists wanted items even when fully stocked', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Drill', quantity: 9, wanted: true),
    );

    await pumpShopping(tester);

    expect(find.text('Drill'), findsOneWidget);
  });

  testWidgets('says so when there is nothing to sell', (tester) async {
    await pumpShopping(tester);
    await openSellTab(tester);

    expect(find.text('Nothing to sell'), findsOneWidget);
  });

  testWidgets('the sell tab lists sellable items', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Old monitor', quantity: 1, sellable: true),
    );
    await repo.upsert(itemFixture(id: 'b', name: 'Flour', quantity: 0));

    await pumpShopping(tester);
    await openSellTab(tester);

    expect(find.text('Old monitor'), findsOneWidget);
    expect(find.text('Flour'), findsNothing);
  });

  testWidgets('the sell tab offers no restock button', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Old monitor', quantity: 1, sellable: true),
    );

    await pumpShopping(tester);
    await openSellTab(tester);

    expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
  });

  testWidgets('Bought adds one, attributed as a restock', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Flour', quantity: 0));
    await pumpShopping(tester);

    await tester.tap(find.byIcon(Icons.add_shopping_cart));
    await tester.pumpAndSettle();

    expect(repo.item('a')!.quantity, 1);
    expect(
      repo.historyFor('a').map((entry) => entry.source),
      contains(AdjustmentSource.restock),
    );
    expect(find.text('Bought 1 Flour'), findsOneWidget);
  });

  // The restocked item drops off the list, so the snackbar is the only
  // remaining handle on it — undo has to live there.
  testWidgets('Undo puts the quantity back', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Flour', quantity: 0, lowStockAt: 1),
    );
    await pumpShopping(tester);

    await tester.tap(find.byIcon(Icons.add_shopping_cart));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(repo.item('a')!.quantity, 0);
    // A correction, not a negative restock: neither feeds the rate, but the
    // history should read as bookkeeping rather than a return to the shop.
    expect(
      repo.historyFor('a').map((entry) => entry.source),
      contains(AdjustmentSource.correction),
    );
  });

  testWidgets('a row opens the item', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Flour', quantity: 0));
    await pumpShopping(tester);

    await tester.tap(find.text('Flour'));
    await tester.pumpAndSettle();

    // The detail screen shows the quantity in its stepper.
    expect(find.text('0'), findsWidgets);
  });
}
