import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/ui/location_picker.dart';

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

  /// Opens the picker from a throwaway screen and records what it returned.
  Future<List<LocationChoice?>> pumpPicker(
    WidgetTester tester, {
    String? excludeSubtreeOf,
    String rootLabel = 'Top level',
    bool allowCreate = false,
    String? createParentId,
  }) async {
    final chosen = <LocationChoice?>[];
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => chosen.add(
                await showLocationPicker(
                  context,
                  repository: repo,
                  title: 'Pick a place',
                  excludeSubtreeOf: excludeSubtreeOf,
                  rootLabel: rootLabel,
                  allowCreate: allowCreate,
                  createParentId: createParentId,
                  now: () => now,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('shows the title and the root option', (tester) async {
    await pumpPicker(tester);

    expect(find.text('Pick a place'), findsOneWidget);
    expect(find.text('Top level'), findsOneWidget);
  });

  testWidgets('says so when there are no places yet', (tester) async {
    await pumpPicker(tester);

    expect(find.textContaining('No places yet'), findsOneWidget);
    expect(find.textContaining('Locations tab'), findsOneWidget);
  });

  testWidgets('points at the create box when it can make one', (tester) async {
    await pumpPicker(tester, allowCreate: true);

    expect(find.textContaining('Type a name below'), findsOneWidget);
  });

  testWidgets('lists every place, flattened', (tester) async {
    final room = await repo.createLocation(name: 'Korytarz', now: now);
    final shelf = await repo.createLocation(
      name: 'Szafka',
      parentId: room.id,
      now: now,
    );
    await repo.createLocation(
      name: 'Najwyższa półka',
      parentId: shelf.id,
      now: now,
    );

    await pumpPicker(tester);

    // Flattened rather than expandable: picking is a single decision, so
    // making the user drill down first would be busywork.
    expect(find.text('Korytarz'), findsOneWidget);
    expect(find.text('Szafka'), findsOneWidget);
    expect(find.text('Najwyższa półka'), findsOneWidget);
  });

  testWidgets('returns the chosen place', (tester) async {
    final room = await repo.createLocation(name: 'Korytarz', now: now);
    final chosen = await pumpPicker(tester);

    await tester.tap(find.text('Korytarz'));
    await tester.pumpAndSettle();

    expect(chosen.single?.location?.id, room.id);
    expect(chosen.single?.id, room.id);
  });

  // A dismissed sheet and a deliberate "nowhere" both arrive as null without
  // the wrapper, and those mean opposite things: leave it alone versus unfile.
  testWidgets('returns a root choice distinct from a dismissal', (
    tester,
  ) async {
    await repo.createLocation(name: 'Korytarz', now: now);
    final chosen = await pumpPicker(tester);

    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();

    expect(chosen.single, isNotNull);
    expect(chosen.single?.location, isNull);
    expect(chosen.single?.id, '');
  });

  testWidgets('returns null when dismissed', (tester) async {
    await repo.createLocation(name: 'Korytarz', now: now);
    final chosen = await pumpPicker(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(chosen.single, isNull);
  });

  testWidgets('honours a custom root label', (tester) async {
    await pumpPicker(tester, rootLabel: 'Anywhere');

    expect(find.text('Anywhere'), findsOneWidget);
    expect(find.text('Top level'), findsNothing);
  });

  group('excludeSubtreeOf', () {
    testWidgets('disables the branch being moved', (tester) async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      await repo.createLocation(name: 'Szafka', parentId: room.id, now: now);
      await repo.createLocation(name: 'Kuchnia', now: now);

      await pumpPicker(tester, excludeSubtreeOf: room.id);

      // A place cannot live inside itself, and offering the choice only to
      // reject it afterwards is worse than not offering it.
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Korytarz'))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Szafka'))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Kuchnia'))
            .enabled,
        isTrue,
      );
    });

    testWidgets('tapping a disabled row does nothing', (tester) async {
      final room = await repo.createLocation(name: 'Korytarz', now: now);
      final chosen = await pumpPicker(tester, excludeSubtreeOf: room.id);

      await tester.tap(find.text('Korytarz'));
      await tester.pumpAndSettle();

      // Still open, nothing returned.
      expect(chosen, isEmpty);
      expect(find.text('Pick a place'), findsOneWidget);
    });
  });
  group('allowCreate', () {
    testWidgets('is off by default', (tester) async {
      await pumpPicker(tester);

      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('creates a top-level room and reports it as new', (
      tester,
    ) async {
      final chosen = await pumpPicker(tester, allowCreate: true);

      expect(find.text('New room'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'korytarz');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(chosen.single?.created, isTrue);
      expect(chosen.single?.location?.name, 'korytarz');
      expect(repo.listLocations().single.createdAt, now);
    });

    testWidgets('files a typed name under the given parent', (tester) async {
      final room = await repo.createLocation(name: 'korytarz', now: now);
      final chosen = await pumpPicker(
        tester,
        allowCreate: true,
        createParentId: room.id,
      );

      expect(find.text('New place in korytarz'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'szafka z lewej');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(chosen.single?.created, isTrue);
      expect(repo.pathLabel(chosen.single!.id), 'korytarz › szafka z lewej');
    });

    // The id is derived from the *folded* name, so a second "Korytarz" is
    // the same record — the user is picking it, not making it.
    testWidgets('an existing name is picked, not reported as new', (
      tester,
    ) async {
      final room = await repo.createLocation(name: 'korytarz', now: now);
      final chosen = await pumpPicker(tester, allowCreate: true);

      await tester.enterText(find.byType(TextField).last, 'Korytarz');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(chosen.single?.created, isFalse);
      expect(chosen.single?.id, room.id);
      expect(repo.listLocations(), hasLength(1));
    });

    testWidgets('a blank name does nothing at all', (tester) async {
      final chosen = await pumpPicker(tester, allowCreate: true);

      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(chosen, isEmpty);
      expect(repo.listLocations(), isEmpty);
      expect(find.text('Pick a place'), findsOneWidget);
    });
  });
}
