import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/sync/sync_service.dart';

import '../support/builders.dart';
import '../support/e2e.dart';
import '../support/github_fake.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;

  setUp(() async {
    resetE2eCopyMemo();
    repo = await ItemRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async {
    await repo.close();
  });

  Future<SyncOutcome> sync(
    GitHubFake github, {
    Future<String?> Function() readPassphrase = readTestPassphrase,
  }) => SyncService(repo).sync(
    owner: 'kuhyx',
    repo: 'syncs',
    token: 'tok',
    readPassphrase: readPassphrase,
    e2eParams: testArgon2,
    httpClient: github.client,
    now: now,
  );

  test('pushes no plaintext field name or value', () async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: now));
    final github = GitHubFake();

    await sync(github);

    expect(github.puts, isNotEmpty);
    for (final put in github.puts) {
      expect(put.content, isNot(contains('Cable')), reason: put.path);
      expect(put.content, isNot(contains('"name"')), reason: put.path);
      expect(put.path, isNot(startsWith('$kSyncPathPrefix/')));
    }
  });

  test('without a passphrase it is locked and writes nothing', () async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: now));
    final github = GitHubFake();

    final outcome = await sync(github, readPassphrase: () async => null);

    expect(outcome.locked, isTrue);
    expect(outcome.pushed, isFalse);
    expect(outcome.itemCount, 1);
    expect(github.puts, isEmpty);
  });

  test('a wrong passphrase is locked and writes nothing more', () async {
    final github = GitHubFake();
    await sync(github);
    final before = github.puts.length;

    final outcome = await sync(github, readPassphrase: () async => 'wrong');

    expect(outcome.locked, isTrue);
    expect(github.puts, hasLength(before));
  });

  test('migrates an old plaintext peer and reads it back sealed', () async {
    final github = GitHubFake(
      dirs: {
        kSyncPathPrefix: ['peer'],
      },
      files: {
        '$kSyncPathPrefix/peer/$kSyncFileName': logToJson({
          'p1': Record(
            id: 'p1',
            fields: {
              kTypeField: (
                kTypeItem,
                const Hlc(wallTimeMs: 1, counter: 0, nodeId: 'peer'),
              ),
              'name': (
                'Theirs',
                const Hlc(wallTimeMs: 1, counter: 0, nodeId: 'peer'),
              ),
            },
          ),
        }),
      },
    );

    final outcome = await sync(github);

    expect(outcome.locked, isFalse);
    expect(repo.listItems().map((i) => i.name), ['Theirs']);
    final copied =
        github.files['${inventoryLayout.prefix}/peer/$kSyncFileName'];
    expect(copied, isNotNull);
    expect(copied, isNot(contains('Theirs')));
    // The old prefix is never deleted or rewritten by the app.
    expect(
      github.files['$kSyncPathPrefix/peer/$kSyncFileName'],
      contains('Theirs'),
    );
  });

  test('a second device with the passphrase reads the first', () async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: now));
    final github = GitHubFake();
    await sync(github);

    final other = await ItemRepository.openInMemory(nodeId: 'other');
    addTearDown(other.close);
    await SyncService(other).sync(
      owner: 'kuhyx',
      repo: 'syncs',
      token: 'tok',
      readPassphrase: readTestPassphrase,
      e2eParams: testArgon2,
      httpClient: github.client,
      now: now,
    );

    expect(other.listItems().map((i) => i.name), ['Cable']);
  });
}
