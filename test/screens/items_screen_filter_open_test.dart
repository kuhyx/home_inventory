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
}
