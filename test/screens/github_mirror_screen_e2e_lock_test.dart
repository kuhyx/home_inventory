import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/github_mirror_screen.dart';
import 'package:home_inventory/sync/github_mirror_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/builders.dart';
import '../support/e2e.dart';
import '../support/github_fake.dart';
import '../support/pump.dart';

void main() {
  final at = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // A device that has never been given the passphrase.
    FlutterSecureStorage.setMockInitialValues({});
    resetE2eForTest();
    repo = await ItemRepository.openInMemory(nodeId: 'me');
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: at));
  });

  tearDown(() async {
    e2eLocked.value = false;
    await repo.close();
  });

  Future<void> pumpAndSync(WidgetTester tester, GitHubFake github) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      GitHubMirrorScreen(
        repository: repo,
        httpClient: github.client,
        now: () => at,
        firebaseFactory: () async => null,
        sessionProbe: () async => false,
        stateStore: InMemorySyncStateStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.bySemanticsLabel('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Sync now'));
    await tester.pumpAndSettle();
  }

  testWidgets('no passphrase: locked, nothing pushed', (tester) async {
    final github = GitHubFake();

    await pumpAndSync(tester, github);

    expect(github.puts, isEmpty);
    expect(e2eLocked.value, isTrue);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('locked')), findsOneWidget);
  });

  testWidgets('saving the passphrase resyncs and unlocks', (tester) async {
    final github = GitHubFake();
    await pumpAndSync(tester, github);

    await tester.tap(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, testPassphrase);
    await tester.tap(find.byIcon(Icons.check));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    expect(e2eLocked.value, isFalse);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(github.puts, isNotEmpty);
    for (final put in github.puts) {
      expect(put.content, isNot(contains('Cable')), reason: put.path);
    }
  });
}
