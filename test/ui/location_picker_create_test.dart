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
