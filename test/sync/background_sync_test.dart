import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/auto_sync.dart';
import 'package:home_inventory/sync/background_sync.dart';
import 'package:home_inventory/sync/github_mirror_actions.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/builders.dart';
import '../support/e2e.dart';
import '../support/github_fake.dart';

void main() {
  final at = DateTime.utc(2026, 11, 27);

  late ItemRepository repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    resetE2eForTest();
    repo = await ItemRepository.openInMemory(nodeId: 'me');
    await repo.upsert(itemFixture(id: 'mine', name: 'Mine', updatedAt: at));
  });

  tearDown(() async {
    await repo.close();
  });

  /// A device with a GitHub token and the shared passphrase.
  void connected({bool passphrase = true}) =>
      FlutterSecureStorage.setMockInitialValues({
        'sync.token': 'gho_tok',
        if (passphrase) ...e2eSecureSeed,
      });

  Future<AutoSyncResult> tick(http.Client client) => runBackgroundSync(
    repo,
    firebaseFactory: () async => null,
    sessionProbe: () async => false,
    stateStore: () async => InMemorySyncStateStore(),
    httpClient: client,
  );

  test('skips a device with no backend set up', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final github = GitHubFake();

    expect(await tick(github.client), AutoSyncResult.skipped);
    expect(github.puts, isEmpty);
  });

  test('pushes the local log when set up', () async {
    connected();
    final github = GitHubFake();

    expect(await tick(github.client), AutoSyncResult.synced);
    expect(github.puts, isNotEmpty);
  });

  test('a Firebase-only device counts as set up', () async {
    FlutterSecureStorage.setMockInitialValues({...e2eSecureSeed});
    var probed = false;

    final result = await runBackgroundSync(
      repo,
      firebaseFactory: () async => null,
      sessionProbe: () async => probed = true,
      stateStore: () async => InMemorySyncStateStore(),
      httpClient: GitHubFake().client,
    );

    expect(probed, isTrue);
    expect(result, AutoSyncResult.synced);
  });

  test('offline fails the tick and keeps the local data', () async {
    connected();
    final dead = http_testing.MockClient(
      (_) async => throw http.ClientException('network is down'),
    );

    expect(await tick(dead), AutoSyncResult.failed);
    expect(repo.item('mine'), isNotNull);
  });

  test('a missing passphrase skips rather than retrying', () async {
    connected(passphrase: false);

    expect(await tick(GitHubFake().client), AutoSyncResult.skipped);
    expect(e2eLocked.value, isTrue);
  });
}
