import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/home_shell.dart';
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

  testWidgets('HomeShell renders the items tab by default', (tester) async {
    await pumpApp(tester, HomeShell(repository: repo, now: () => at));
    await tester.pump();

    expect(find.byType(ItemsScreen), findsOneWidget);
  });

  // NavigationBar asserts destinations.length >= 2, and that assert is
  // stripped from release builds — so a single-destination bar looks fine on
  // a device and blows up only in debug. This is the guard against adding one
  // back before there is a second tab.
  testWidgets('HomeShell shows no nav bar while there is one tab', (
    tester,
  ) async {
    await pumpApp(tester, HomeShell(repository: repo, now: () => at));
    await tester.pump();

    expect(find.byType(NavigationBar), findsNothing);
  });
}
