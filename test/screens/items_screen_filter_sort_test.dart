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
}
