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

  testWidgets('shows the empty state before anything is added', (tester) async {
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
  testWidgets('the summary strip says item, singular, for one', (tester) async {
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
  testWidgets('the add sheet defaults to the filtered place', (tester) async {
    final room = await repo.createLocation(name: 'korytarz', now: at);
    await repo.createLocation(name: 'szafka', parentId: room.id, now: at);
    await pumpList(
      tester,
      requested: ItemFilter(locationIds: repo.subtreeIds(room.id)),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('korytarz'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Buty');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.listItems().single.locationId, room.id);
  });
}
