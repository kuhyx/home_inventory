import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';

import '../support/builders.dart';
import '../support/github_fake.dart';

const _settings = SyncSettings(
  owner: 'kuhyx',
  repo: 'syncs',
  token: 'tok',
);

Hlc _hlc(int ms, {String node = 'peer'}) =>
    Hlc(wallTimeMs: ms, counter: 0, nodeId: node);

Record _peerItem(String id, String name) => Record(
  id: id,
  fields: {
    kTypeField: (kTypeItem, _hlc(1)),
    'name': (name, _hlc(1)),
    'quantity': (1, _hlc(1)),
  },
);

Record _adjustment(String id, DateTime at) => Record(
  id: id,
  fields: {
    kTypeField: (kTypeAdjustment, _hlc(1)),
    'item_id': ('peer-1', _hlc(1)),
    'delta': (-1, _hlc(1)),
    kAtField: (at.toIso8601String(), _hlc(1)),
    'source': ('use', _hlc(1)),
  },
);

void main() {
  final now = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;
  late SyncService service;

  setUp(() async {
    repo = await ItemRepository.openInMemory(nodeId: 'me');
    service = SyncService(repo);
  });

  tearDown(() async {
    await repo.close();
  });

  const myPath = '$kSyncPathPrefix/me/$kSyncFileName';
  String peerPath(String id) => '$kSyncPathPrefix/$id/$kSyncFileName';

  test('pushes local items on a first sync with no peers', () async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: now));
    final github = GitHubFake();

    final outcome = await service.sync(
      _settings,
      httpClient: github.client,
      now: now,
    );

    expect(outcome.pushed, isTrue);
    expect(outcome.itemCount, 1);
    expect(github.puts.single.path, myPath);
    expect(github.puts.single.content, contains('Cable'));
  });

  test('pulls a peer item and keeps its own', () async {
    await repo.upsert(itemFixture(id: 'mine', name: 'Mine', updatedAt: now));
    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['peer'],
      },
      files: {
        peerPath('peer'): logToJson({'p1': _peerItem('p1', 'Theirs')}),
      },
    );

    await service.sync(_settings, httpClient: github.client, now: now);

    final names = repo.listItems().map((i) => i.name).toSet();
    expect(names, {'Mine', 'Theirs'});
  });

  test('skips its own directory when pulling', () async {
    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['me'],
      },
      files: {
        myPath: logToJson({'x': _peerItem('x', 'Stale')}),
      },
    );

    await service.sync(_settings, httpClient: github.client, now: now);

    // Its own remote file is not pulled back in, so the empty local log wins.
    expect(repo.listItems(), isEmpty);
  });

  // THE regression test for the retention design. Without the prune inside
  // `decode`, syncLog merges the peer's aged-out record into the push, so the
  // record comes straight back and gets re-committed on every single sync,
  // forever, and the log never shrinks.
  test('does not push back an ancient adjustment pulled from a peer', () async {
    final ancient = now.subtract(const Duration(days: 400));
    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['peer'],
      },
      files: {
        peerPath('peer'): logToJson({
          'old': _adjustment('old', ancient),
          'peer-1': _peerItem('peer-1', 'Theirs'),
        }),
      },
    );

    await service.sync(_settings, httpClient: github.client, now: now);

    expect(github.puts.single.content, isNot(contains('old')));
    expect(repo.exportLog().containsKey('old'), isFalse);
    // The peer's live item still made it through — the prune is targeted,
    // not a blanket drop of everything the peer sent.
    expect(repo.exportLog().containsKey('peer-1'), isTrue);
  });

  test('keeps a recent adjustment from a peer', () async {
    final recent = now.subtract(const Duration(days: 5));
    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['peer'],
      },
      files: {
        peerPath('peer'): logToJson({
          'fresh': _adjustment('fresh', recent),
          'peer-1': _peerItem('peer-1', 'Theirs'),
        }),
      },
    );

    await service.sync(_settings, httpClient: github.client, now: now);

    expect(repo.exportLog().containsKey('fresh'), isTrue);
    expect(repo.historyFor('peer-1'), hasLength(1));
  });

  // Per-field last-writer-wins is the whole reason for the record shape: a
  // peer editing the location must not lose to a local quantity edit, and
  // vice versa.
  test('merges concurrent edits to different fields of one item', () async {
    await repo.upsert(
      itemFixture(id: 'shared', name: 'Flour', quantity: 5, updatedAt: now),
    );
    await repo.adjustQuantity('shared', -2, AdjustmentSource.use, now: now);

    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['peer'],
      },
      files: {
        peerPath('peer'): logToJson({
          'shared': Record(
            id: 'shared',
            fields: {
              kTypeField: (kTypeItem, _hlc(1)),
              // Written far in the future so it definitively wins its field.
              'room': ('Pantry', _hlc(99999999999999)),
            },
          ),
        }),
      },
    );

    await service.sync(_settings, httpClient: github.client, now: now);

    final merged = repo.item('shared')!;
    expect(merged.room, 'Pantry');
    expect(merged.quantity, 3);
  });

  test('surfaces a missing repo rather than swallowing it', () async {
    final github = GitHubFake(repoExists: false);

    await expectLater(
      service.sync(_settings, httpClient: github.client, now: now),
      throwsA(isA<GitHubSyncError>()),
    );
  });

  test('defaults its clock when none is given', () async {
    await repo.upsert(itemFixture(updatedAt: DateTime.now()));
    final github = GitHubFake();

    final outcome = await service.sync(_settings, httpClient: github.client);

    expect(outcome.pushed, isTrue);
  });
}
