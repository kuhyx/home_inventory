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

  Future<void> pumpList(WidgetTester tester) async {
    await pumpApp(tester, ItemsScreen(repository: repo, now: () => at));
    await tester.pump();
  }

  /// Pumps past the search debounce plus the resulting stream emission.
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('shows the empty state before anything is added', (
    tester,
  ) async {
    await pumpList(tester);

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Tap + to add the first thing you own.'), findsOneWidget);
  });

  testWidgets('lists items newest-edited first', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Older', updatedAt: DateTime.utc(2026, 3)),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Newer', updatedAt: DateTime.utc(2026, 5)),
    );

    await pumpList(tester);

    final tiles = tester.widgetList<Text>(find.byType(Text)).toList();
    final names = tiles.map((t) => t.data).whereType<String>().toList();
    expect(names.indexOf('Newer'), lessThan(names.indexOf('Older')));
  });

  testWidgets('the summary strip counts items and things to buy', (
    tester,
  ) async {
    await repo.upsert(itemFixture(id: 'a', quantity: 5));
    await repo.upsert(itemFixture(id: 'b', quantity: 0));

    await pumpList(tester);

    expect(find.text('2 items · 1 to buy'), findsOneWidget);
  });

  // Spotted on the device: the strip read "1 items".
  testWidgets('the summary strip says item, singular, for one', (
    tester,
  ) async {
    await repo.upsert(itemFixture(id: 'a', quantity: 5));

    await pumpList(tester);

    expect(find.text('1 item · 0 to buy'), findsOneWidget);
  });

  testWidgets('the summary strip hides itself when empty', (tester) async {
    await pumpList(tester);

    expect(find.textContaining('items ·'), findsNothing);
  });

  testWidgets('search filters the list after the debounce', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Cable'));
    await repo.upsert(itemFixture(id: 'b', name: 'Flour'));
    await pumpList(tester);

    await tester.enterText(find.byType(TextField).first, 'cab');
    await settleSearch(tester);

    expect(find.text('Cable'), findsOneWidget);
    expect(find.text('Flour'), findsNothing);
  });

  // A filtered-empty list must not read as an empty inventory, or the user
  // thinks their data is gone.
  testWidgets('a search with no matches says so distinctly', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Cable'));
    await pumpList(tester);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await settleSearch(tester);

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('opens the add sheet from the button', (tester) async {
    await pumpList(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add an item'), findsOneWidget);
  });

  testWidgets('opens an item when its row is tapped', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Cable', quantity: 4));
    await pumpList(tester);

    await tester.tap(find.text('Cable'));
    await tester.pumpAndSettle();

    // The detail screen puts the name in the app bar and the quantity in the
    // stepper, so both appear once we have navigated.
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('opens the sync screen from the header', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await pumpList(tester);

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the filter badge counts active facets', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', quantity: 7, category: 'Tools'),
    );
    await pumpList(tester);

    // No badge label at all while nothing is restricted — a "0" would read as
    // a filter that is on and matching nothing.
    expect(find.text('0'), findsNothing);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Tools'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Cable'), findsOneWidget);
  });

  testWidgets('dismissing the filter sheet changes nothing', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', quantity: 7, category: 'Tools'),
    );
    await pumpList(tester);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Tools'));
    await tester.pump();
    // Back out instead of applying: the selection must not leak through.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsNothing);
  });

  testWidgets('the sort menu reorders the list', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Zinc', updatedAt: DateTime.utc(2026, 5)),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Anchor', updatedAt: DateTime.utc(2026, 3)),
    );
    await pumpList(tester);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name (A-Z)').last);
    await tester.pumpAndSettle();

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(names.indexOf('Anchor'), lessThan(names.indexOf('Zinc')));
  });

  // The locations tab hands a filter across; the items tab has to adopt it
  // even though it is already built and sitting in the IndexedStack.
  testWidgets('adopts a filter pushed in from another tab', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: 'office'),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Flour', locationId: 'kitchen'),
    );

    await pumpApp(tester, ItemsScreen(repository: repo, now: () => at));
    await tester.pump();
    await pumpApp(
      tester,
      ItemsScreen(
        repository: repo,
        now: () => at,
        requestedFilter: const ItemFilter(locationIds: {'kitchen'}),
      ),
    );
    await tester.pump();

    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('Cable'), findsNothing);
  });

  testWidgets('a pushed filter clears a stale search term', (tester) async {
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: 'office'),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Flour', locationId: 'kitchen'),
    );
    await pumpList(tester);

    await tester.enterText(find.byType(TextField).first, 'cab');
    await settleSearch(tester);
    await pumpApp(
      tester,
      ItemsScreen(
        repository: repo,
        now: () => at,
        requestedFilter: const ItemFilter(locationIds: {'kitchen'}),
      ),
    );
    await tester.pump();

    // Without the clear this would be "No matches": 'cab' AND room=Kitchen.
    expect(find.text('Flour'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      '',
    );
  });

  // Rebuilding with the *same instance* must not stomp on whatever the user
  // has changed since — the shell hands the same object back on every tab
  // switch.
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

  // Tapping the same room twice is a second genuine request: the user may
  // have cleared the filter in between, and comparing by value rather than
  // identity would make that tap do nothing at all.
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
