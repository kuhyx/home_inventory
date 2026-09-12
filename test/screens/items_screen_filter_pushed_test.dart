import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/screens/items_screen.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pumpList(WidgetTester tester, {ItemFilter? requested}) async {
    await pumpApp(
      tester,
      ItemsScreen(repository: repo, now: () => at, requestedFilter: requested),
    );
    await tester.pump();
  }

  /// Pumps past the search debounce plus the resulting stream emission.
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('the same filter instance is not re-adopted', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: 'office'),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Flour', locationId: 'kitchen'),
    );
    const pushed = ItemFilter(locationIds: {'kitchen'});

    await pumpApp(
      tester,
      ItemsScreen(repository: repo, now: () => at, requestedFilter: pushed),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'flo');
    await settleSearch(tester);
    await pumpApp(
      tester,
      ItemsScreen(repository: repo, now: () => at, requestedFilter: pushed),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'flo',
    );
  });
  testWidgets('a re-requested equal filter is adopted again', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: 'office'),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Flour', locationId: 'kitchen'),
    );

    await pumpApp(
      tester,
      ItemsScreen(
        repository: repo,
        now: () => at,
        // Built the way HomeShell builds it — at run time, so each tap is a
        // fresh object rather than a canonicalised const.
        requestedFilter: ItemFilter(locationIds: {'kitchen'}),
      ),
    );
    await tester.pump();
    // Stand in for the user widening the filter again from the sheet.
    await tester.enterText(find.byType(TextField).first, 'cab');
    await settleSearch(tester);
    await pumpApp(
      tester,
      ItemsScreen(
        repository: repo,
        now: () => at,
        requestedFilter: ItemFilter(locationIds: {'kitchen'}),
      ),
    );
    await tester.pump();

    expect(find.text('Flour'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '',
    );
  });
  group('scan to restock', () {
    testWidgets('restocks whatever the code is linked to', (tester) async {
      await repo.upsert(itemFixture(id: 'flour', name: 'Flour', quantity: 1));
      await repo.linkBarcode(code: '590', itemId: 'flour', amount: 500);
      await pumpList(tester);

      await tester.tap(find.byTooltip('Scan to restock'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '590');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(repo.item('flour')!.quantity, 501);
      expect(find.text('Restocked Flour'), findsOneWidget);
    });

    // Silently doing nothing is how a user ends up tapping the same button
    // three times wondering which part is broken.
    testWidgets('says so when nothing is linked to the code', (tester) async {
      await pumpList(tester);

      await tester.tap(find.byTooltip('Scan to restock'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '590');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('No item is linked to 590'), findsOneWidget);
    });

    testWidgets('a cancelled prompt changes nothing', (tester) async {
      await repo.upsert(itemFixture(id: 'flour', quantity: 1));
      await repo.linkBarcode(code: '590', itemId: 'flour');
      await pumpList(tester);

      await tester.tap(find.byTooltip('Scan to restock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.item('flour')!.quantity, 1);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
