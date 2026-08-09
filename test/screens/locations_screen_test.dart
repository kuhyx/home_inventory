import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/locations_screen.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  /// Which place the screen asked the shell to show.
  final selections = <String>[];

  setUp(selections.clear);

  Future<void> pumpLocations(WidgetTester tester) async {
    await pumpApp(
      tester,
      LocationsScreen(
        repository: repo,
        onSelect: selections.add,
        now: () => now,
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the empty state with nothing filed', (tester) async {
    await pumpLocations(tester);

    expect(find.text('No locations yet'), findsOneWidget);
  });

  testWidgets('lists places with their item counts', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    final kitchen = await repo.createLocation(name: 'Kitchen', now: now);
    await repo.upsert(itemFixture(id: 'a', locationId: office.id));
    await repo.upsert(itemFixture(id: 'b', locationId: office.id));
    await repo.upsert(itemFixture(id: 'c', locationId: kitchen.id));

    await pumpLocations(tester);

    expect(find.text('Office'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  // The whole point of making places records: a room can exist before there
  // is anything in it.
  testWidgets('a place with no items still shows', (tester) async {
    await repo.createLocation(name: 'Garaż', now: now);

    await pumpLocations(tester);

    expect(find.text('Garaż'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);
  });

  testWidgets('children stay hidden until the parent is expanded', (
    tester,
  ) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await repo.createLocation(name: 'Drawer 2', parentId: office.id, now: now);
    await pumpLocations(tester);

    expect(find.text('Drawer 2'), findsNothing);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer 2'), findsOneWidget);
  });

  testWidgets('collapsing hides them again', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await repo.createLocation(name: 'Drawer 2', parentId: office.id, now: now);
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();

    expect(find.text('Drawer 2'), findsNothing);
  });

  // The feature as asked for: korytarz → szafka → półka → sekcja.
  testWidgets('nests as deep as the user likes', (tester) async {
    final l1 = await repo.createLocation(name: 'korytarz', now: now);
    final l2 = await repo.createLocation(
      name: 'szafka z lewej',
      parentId: l1.id,
      now: now,
    );
    final l3 = await repo.createLocation(
      name: 'najwyższa półka',
      parentId: l2.id,
      now: now,
    );
    await repo.createLocation(
      name: 'sekcja przy drzwiach',
      parentId: l3.id,
      now: now,
    );
    await pumpLocations(tester);

    for (final name in ['korytarz', 'szafka z lewej', 'najwyższa półka']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    expect(find.text('sekcja przy drzwiach'), findsOneWidget);
  });

  testWidgets('the arrow selects the place', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await pumpLocations(tester);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();

    expect(selections, [office.id]);
  });

  testWidgets('tapping a childless row selects it', (tester) async {
    final office = await repo.createLocation(name: 'Office', now: now);
    await pumpLocations(tester);

    await tester.tap(find.text('Office'));
    await tester.pump();

    expect(selections, [office.id]);
  });

  group('adding', () {
    testWidgets('the FAB adds a top-level room', (tester) async {
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Piwnica');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Piwnica'), findsOneWidget);
      expect(repo.listLocations().single.name, 'Piwnica');
    });

    testWidgets('adds a place inside another and opens it', (tester) async {
      await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a place inside'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Szuflada');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Already expanded, or the user cannot see what they just made.
      expect(find.text('Szuflada'), findsOneWidget);
    });

    testWidgets('refuses an empty name', (tester) async {
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give it a name'), findsOneWidget);
      expect(repo.listLocations(), isEmpty);
    });

    // Ids are derived from (parent, folded name), so two same-named siblings
    // would collapse onto one record. Better to say so than to silently merge.
    testWidgets('refuses a duplicate sibling name', (tester) async {
      await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'office');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('There is already a "office" here'), findsOneWidget);
    });

    testWidgets('cancelling adds nothing', (tester) async {
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Piwnica');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repo.listLocations(), isEmpty);
    });
  });

  group('renaming', () {
    testWidgets('renames in place', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Biuro');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Biuro'), findsOneWidget);
      // Same record, so anything filed here followed the rename.
      expect(repo.location(office.id)?.name, 'Biuro');
    });

    testWidgets('keeping the same name is not a collision', (tester) async {
      await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already a'), findsNothing);
    });
  });

  group('moving', () {
    testWidgets('moves a place under another', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      final shed = await repo.createLocation(name: 'Shed', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shed').last);
      await tester.pumpAndSettle();

      expect(repo.location(office.id)?.parentId, shed.id);
    });

    testWidgets('moves a place back to the top level', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      final drawer = await repo.createLocation(
        name: 'Drawer',
        parentId: office.id,
        now: now,
      );
      await pumpLocations(tester);

      await tester.tap(find.text('Office'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Top level'));
      await tester.pumpAndSettle();

      expect(repo.location(drawer.id)?.parentId, isNull);
    });

    // The picker greys out the invalid branch, so this cannot be reached by
    // tapping — but a concurrent move on another device can make the target
    // become a descendant between opening the sheet and choosing a row, and
    // then the repo refuses it. The user has to be told, not left wondering.
    testWidgets('says so when the move is refused', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      final drawer = await repo.createLocation(name: 'Drawer', now: now);
      await pumpLocations(tester);

      // Open the picker for Drawer while both are still top-level, so nothing
      // is greyed out yet.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Drawer'),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();

      // The other device's move lands: Office is now inside Drawer, so moving
      // Drawer into Office would close a loop.
      await repo.moveLocation(office.id, drawer.id, now: now);
      await tester.tap(find.text('Office').last);
      await tester.pumpAndSettle();

      expect(
        find.text('That would put a place inside itself.'),
        findsOneWidget,
      );
    });

    testWidgets('dismissing the picker moves nothing', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      await repo.createLocation(name: 'Shed', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      // Tap the barrier rather than a row.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(repo.location(office.id)?.parentId, isNull);
    });
  });

  group('deleting', () {
    testWidgets('deletes after confirming', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repo.location(office.id), isNull);
    });

    testWidgets('says what happens to the things inside', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      await repo.upsert(itemFixture(id: 'a', locationId: office.id));
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // The row subtitle says '1 item' too, so match the sentence that
      // only the dialog has.
      expect(find.textContaining('will show as unfiled'), findsOneWidget);
    });

    testWidgets('cancelling keeps the place', (tester) async {
      final office = await repo.createLocation(name: 'Office', now: now);
      await pumpLocations(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repo.location(office.id), isNotNull);
    });
  });
}
