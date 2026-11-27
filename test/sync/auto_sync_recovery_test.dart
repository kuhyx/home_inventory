// End to end over the real tick: AutoSync driving runBackgroundSync against
// a fake GitHub that is down, then comes back. The write made while it was
// down must reach the remote on an automatic retry, with no "Sync now" tap.
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/auto_sync.dart';
import 'package:home_inventory/sync/background_sync.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/builders.dart';
import '../support/e2e.dart';
import '../support/github_fake.dart';

/// How the remote fails before it recovers.
enum _Outage {
  /// Every request fails the way a dropped network does.
  offline,

  /// Every GET answers 200 with the wrong JSON shape, so the client's cast
  /// throws a TypeError: a Dart Error, not an Exception.
  garbled,
}

/// A [GitHubFake] behind a switch: while [down], it fails as [outage] says.
class _FlakyGitHub {
  _FlakyGitHub(this.outage);

  final _Outage outage;
  final GitHubFake github = GitHubFake();
  bool down = true;

  http.Client get client => http_testing.MockClient((request) async {
    if (down && outage == _Outage.offline) {
      throw http.ClientException('network is down');
    }
    if (down && request.method == 'GET') return http.Response('[]', 200);
    // MockClient hands over a finalized request; forward a fresh copy.
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes;
    return await http.Response.fromStream(await github.client.send(copy));
  });
}

/// Polls [done] on real time until it holds, failing after a few seconds.
Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  final at = DateTime.utc(2026, 11, 27);

  late ItemRepository repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'sync.token': 'gho_tok',
      ...e2eSecureSeed,
    });
    resetE2eForTest();
    repo = await ItemRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async {
    await repo.close();
  });

  /// A write made while the remote fails as [outage] is pushed by the next
  /// automatic retry once it recovers, and a second device then sees it.
  Future<void> writeDuringOutageIsPushed(_Outage outage) async {
    final remote = _FlakyGitHub(outage);
    final state = InMemorySyncStateStore();
    // Every tick that ran, and how each that returned ended (a tick that
    // throws returns nothing, so it shows up in [attempts] only).
    var attempts = 0;
    final results = <AutoSyncResult>[];
    final auto = AutoSync(
      repository: repo,
      run: () async {
        attempts++;
        final result = await runBackgroundSync(
          repo,
          firebaseFactory: () async => null,
          sessionProbe: () async => false,
          stateStore: () async => state,
          httpClient: remote.client,
        );
        results.add(result);
        return result;
      },
      debounce: const Duration(milliseconds: 20),
      firstRetry: const Duration(milliseconds: 100),
      maxRetry: const Duration(milliseconds: 200),
      interval: const Duration(hours: 1),
    );
    addTearDown(auto.dispose);

    auto.start();
    await _until(() => attempts > 0, 'the launch tick');

    // Written while the remote is down: kept locally, not pushed.
    await repo.upsert(itemFixture(id: 'cable', name: 'Cable', updatedAt: at));
    final failedSoFar = attempts;
    await _until(() => attempts > failedSoFar, 'a tick after the write');
    expect(results, isNot(contains(AutoSyncResult.synced)));
    expect(remote.github.puts, isEmpty);
    expect(repo.item('cable')?.name, 'Cable');

    // The remote comes back; nothing calls syncNow or taps a button.
    remote.down = false;
    await _until(
      () => results.contains(AutoSyncResult.synced),
      'the retry after recovery',
    );
    expect(remote.github.puts, isNotEmpty);

    // A second device pulling from the remote sees the offline write.
    final other = await ItemRepository.openInMemory(nodeId: 'other');
    addTearDown(other.close);
    await SyncService(other).sync(
      owner: 'kuhyx',
      repo: 'syncs',
      token: 'tok',
      readPassphrase: readTestPassphrase,
      e2eParams: testArgon2,
      httpClient: remote.github.client,
      now: at,
    );
    expect(other.listItems().map((i) => i.name), ['Cable']);
  }

  test(
    'a write made while offline is pushed by the next automatic retry '
    'once the remote recovers',
    () => writeDuringOutageIsPushed(_Outage.offline),
  );

  test('a sync that throws a Dart Error (TypeError) is retried too', () async {
    await writeDuringOutageIsPushed(_Outage.garbled);
  });
}
