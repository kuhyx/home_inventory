import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import '../support/builders.dart';
import '../support/e2e.dart';
import '../support/github_fake.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27);

  setUp(resetE2eForTest);

  // Sync now starts by itself (launch, resume, after a write), so the user can
  // be adding an item while a tick is on the network. The tick must merge its
  // result into the store, not overwrite it with the snapshot it started from.
  test('a write made while a sync is in flight survives the merge', () async {
    final repo = await ItemRepository.openInMemory(nodeId: 'me');
    addTearDown(repo.close);
    await repo.upsert(itemFixture(id: 'old', name: 'Old', updatedAt: now));
    final github = GitHubFake();
    var wrote = false;
    final client = http_testing.MockClient((request) async {
      // This device's own log file: written after the peers were read, so
      // after the tick took its local snapshot.
      final ownFile = request.url.path.endsWith('/me/$kSyncFileName');
      if (request.method == 'PUT' && ownFile && !wrote) {
        wrote = true;
        await repo.upsert(itemFixture(id: 'new', name: 'New', updatedAt: now));
      }
      // MockClient hands over a finalized request, which cannot be sent
      // again, so the fake gets a copy.
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return http.Response.fromStream(await github.client.send(copy));
    });

    await SyncService(repo).sync(
      owner: 'kuhyx',
      repo: 'syncs',
      token: 'tok',
      readPassphrase: readTestPassphrase,
      e2eParams: testArgon2,
      httpClient: client,
      now: now,
    );

    expect(wrote, isTrue);
    expect(repo.item('old'), isNotNull);
    expect(repo.item('new'), isNotNull, reason: 'the in-flight write is kept');
  });
}
