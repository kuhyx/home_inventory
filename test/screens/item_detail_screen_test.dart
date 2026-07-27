import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/screens/item_detail_screen.dart';
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

  Future<void> pumpDetail(WidgetTester tester, {String id = 'i1'}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      ItemDetailScreen(repository: repo, itemId: id, now: () => at),
    );
    await tester.pump();
  }

  testWidgets('shows a spinner for an unknown item', (tester) async {
    await pumpDetail(tester, id: 'nope');

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the name, quantity, location and notes', (tester) async {
    await repo.upsert(
      itemFixture(
        name: 'Flour',
        quantity: 2.5,
        unit: 'kg',
        room: 'Kitchen',
        container: 'Pantry',
        category: 'Food',
        notes: 'wholemeal',
        updatedAt: at,
      ),
    );

    await pumpDetail(tester);

    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('Kitchen › Pantry'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('wholemeal'), findsOneWidget);
  });

  testWidgets('omits empty optional rows', (tester) async {
    await repo.upsert(itemFixture(name: 'Bare', quantity: 1, updatedAt: at));

    await pumpDetail(tester);

    expect(find.byIcon(Icons.place_outlined), findsNothing);
    expect(find.byIcon(Icons.sell_outlined), findsNothing);
    expect(find.byIcon(Icons.notes_outlined), findsNothing);
  });

  // The two stepper buttons must record *different* sources, because only
  // `use` feeds the consumption rate.
  testWidgets('minus records use, plus records restock', (tester) async {
    await repo.upsert(itemFixture(quantity: 5, updatedAt: at));

    await pumpDetail(tester);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(repo.item('i1')!.quantity, 4);
    expect(repo.historyFor('i1').last.source, AdjustmentSource.use);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(repo.item('i1')!.quantity, 5);
    expect(repo.historyFor('i1').last.source, AdjustmentSource.restock);
  });

  testWidgets('shows the low badge when under the threshold', (tester) async {
    await repo.upsert(
      itemFixture(quantity: 1, lowStockAt: 2, updatedAt: at),
    );

    await pumpDetail(tester);

    expect(find.text('Low'), findsOneWidget);
  });

  testWidgets('lists history newest first', (tester) async {
    await repo.upsert(itemFixture(quantity: 10, updatedAt: at));
    await repo.adjustQuantity(
      'i1',
      -2,
      AdjustmentSource.use,
      now: at.add(const Duration(days: 1)),
    );

    await pumpDetail(tester);

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Used 2'), findsOneWidget);
    expect(find.text('Added 10 to start'), findsOneWidget);
  });

  testWidgets('describes a recount distinctly from usage', (tester) async {
    await repo.upsert(itemFixture(quantity: 10, updatedAt: at));
    await repo.setQuantity(
      'i1',
      6,
      AdjustmentSource.correction,
      now: at.add(const Duration(days: 1)),
    );

    await pumpDetail(tester);

    expect(find.textContaining('Recounted'), findsOneWidget);
  });

  testWidgets('hides the history section when there is none', (tester) async {
    await repo.upsert(itemFixture(quantity: 0, updatedAt: at));

    await pumpDetail(tester);

    expect(find.text('History'), findsNothing);
  });

  // The projection is informational; when there is not enough evidence the
  // correct output is nothing at all.
  testWidgets('shows no rate hint without enough usage', (tester) async {
    await repo.upsert(itemFixture(quantity: 5, updatedAt: at));

    await pumpDetail(tester);

    expect(find.textContaining('days left'), findsNothing);
  });

  testWidgets('shows the rate hint once there is enough usage', (
    tester,
  ) async {
    await repo.upsert(
      itemFixture(quantity: 40, lowStockAt: 10, updatedAt: at),
    );
    for (var i = 0; i < 20; i++) {
      await repo.adjustQuantity(
        'i1',
        -1,
        AdjustmentSource.use,
        now: at.subtract(Duration(days: 40 - (i * 2))),
      );
    }

    await pumpDetail(tester);

    expect(find.textContaining('days left'), findsOneWidget);
  });

  testWidgets('opens the edit form', (tester) async {
    await repo.upsert(itemFixture(name: 'Flour', updatedAt: at));

    await pumpDetail(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(ItemFormScreen), findsOneWidget);
    expect(find.text('Edit item'), findsOneWidget);
  });
}
