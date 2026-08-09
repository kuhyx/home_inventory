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

  testWidgets('tapping a place shows it on the items tab', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: at);
    final kitchen = await repo.createLocation(name: 'Kitchen', now: at);
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: office.id),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Flour', locationId: kitchen.id),
    );
    await pumpShell(tester);

    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_forward).first,
    );
    await tester.pumpAndSettle();

    // Siblings order by name, so Kitchen leads.
    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('Cable'), findsNothing);
  });

  testWidgets('tapping a nested place narrows to it', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: at);
    final drawer = await repo.createLocation(
      name: 'Drawer 2',
      parentId: office.id,
      now: at,
    );
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: drawer.id),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Stapler', locationId: office.id),
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

  // Asking for a room means the room *and everything in it*. Filtering on the
  // one id alone would hide whatever sits on its shelves, which reads as data
  // loss rather than as a narrow filter.
  testWidgets('showing a place includes everything nested inside', (
    tester,
  ) async {
    final office = await repo.createLocation(name: 'Office', now: at);
    final drawer = await repo.createLocation(
      name: 'Drawer 2',
      parentId: office.id,
      now: at,
    );
    await repo.upsert(
      itemFixture(id: 'a', name: 'Cable', locationId: drawer.id),
    );
    await repo.upsert(
      itemFixture(id: 'b', name: 'Stapler', locationId: office.id),
    );
    await repo.upsert(itemFixture(id: 'c', name: 'Flour'));
    await pumpShell(tester);

    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_forward).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Stapler'), findsOneWidget);
    expect(find.text('Cable'), findsOneWidget);
    expect(find.text('Flour'), findsNothing);
  });
}
