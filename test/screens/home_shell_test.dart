import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/home_shell.dart';
import 'package:home_inventory/screens/items_screen.dart';
import 'package:home_inventory/screens/locations_screen.dart';
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

  Future<void> pumpShell(WidgetTester tester) async {
    await pumpApp(tester, HomeShell(repository: repo, now: () => at));
    await tester.pump();
  }

  testWidgets('opens on the items tab', (tester) async {
    await pumpShell(tester);

    expect(find.byType(ItemsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  // IndexedStack builds every destination up front, so all three screens
  // subscribe to the store's change stream at once. This is the regression
  // guard for that: a single-subscription stream would throw here and nowhere
  // else, since the per-screen tests each mount exactly one.
  testWidgets('all three destinations can watch the store at once', (
    tester,
  ) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Cable', room: 'Office'));

    await pumpShell(tester);

    // skipOffstage: false because IndexedStack keeps the unselected tabs
    // built but offstage — which is precisely the condition under test.
    expect(find.byType(ItemsScreen), findsOneWidget);
    expect(
      find.byType(LocationsScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(ShoppingScreen, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches to the shopping tab', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Shopping'));
    await tester.pumpAndSettle();

    expect(find.text('To buy'), findsOneWidget);
  });

  testWidgets('tapping a room shows it on the items tab', (tester) async {
    await repo.upsert(itemFixture(id: 'a', name: 'Cable', room: 'Office'));
    await repo.upsert(itemFixture(id: 'b', name: 'Flour', room: 'Kitchen'));
    await pumpShell(tester);

    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_forward).first,
    );
    await tester.pumpAndSettle();

    // Back on the items tab, narrowed to the busiest room's contents. Both
    // rooms hold one item, so the tree orders them by name: Kitchen first.
    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('Cable'), findsNothing);
  });

  testWidgets('tapping a container narrows to it', (tester) async {
    await repo.upsert(
      itemFixture(
        id: 'a',
        name: 'Cable',
        room: 'Office',
        container: 'Drawer 2',
      ),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Stapler', room: 'Office'),
    );
    await pumpShell(tester);

    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drawer 2'));
    await tester.pumpAndSettle();

    expect(find.text('Cable'), findsOneWidget);
    expect(find.text('Stapler'), findsNothing);
  });

  // 'Loose in the room' is an empty container name, which is a real value —
  // not "no container filter". Getting this wrong silently shows the whole
  // room instead of the handful of items lying loose in it.
  testWidgets('tapping the loose-items row narrows to no container', (
    tester,
  ) async {
    await repo.upsert(
      itemFixture(
        id: 'a',
        name: 'Cable',
        room: 'Office',
        container: 'Drawer 2',
      ),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Stapler', room: 'Office'),
    );
    await pumpShell(tester);

    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loose in the room'));
    await tester.pumpAndSettle();

    expect(find.text('Stapler'), findsOneWidget);
    expect(find.text('Cable'), findsNothing);
  });
}
