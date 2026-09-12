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
