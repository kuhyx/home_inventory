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
}
