// A manual, against-real-GitHub check that sync actually works.
//
// Deliberately outside `lib/`: this is a plain Dart CLI, so `dart:io` is fine
// here and would not be inside the app's graph. It is not part of the test
// suite — it talks to the network.
//
// Usage, from the repo root:
//
//   GITHUB_TOKEN=<pat> dart run tool/sync_smoke.dart
//
// It reads the token from the environment rather than the app's keystore
// because a CLI has no secure storage; a fine-grained PAT with contents
// read/write on kuhyx/syncs is enough.

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final token = Platform.environment['GITHUB_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('Set GITHUB_TOKEN to a PAT with contents access.');
    exitCode = 2;
    return;
  }

  // A throwaway node id and a throwaway directory: this must never write into
  // a real device's slot in the repo, or it would clobber that device's file.
  final dir = await Directory.systemTemp.createTemp('inventory-smoke');
  final repository = await ItemRepository.openWith(
    persistence: FileLogPersistence(
      File(p.join(dir.path, ItemRepository.logFileName)),
    ),
    nodeId: 'smoke-${DateTime.now().millisecondsSinceEpoch}',
  );

  final owner = Platform.environment['SYNC_OWNER'] ?? 'kuhyx';
  final repo = Platform.environment['SYNC_REPO'] ?? 'syncs';

  try {
    stdout.writeln(
      'Syncing as ${repository.nodeId} against $owner/$repo …',
    );
    final outcome = await SyncService(
      repository,
    ).sync(owner: owner, repo: repo, token: token);
    stdout.writeln('Merged ${outcome.itemCount} items.');
    for (final item in repository.listItems()) {
      final where = item.location.isEmpty ? 'nowhere recorded' : item.location;
      stdout.writeln('  ${item.name}  ×${item.quantity}  ($where)');
    }
    if (outcome.itemCount == 0) {
      stdout.writeln('Nothing found — has a device pushed yet?');
    }
  } on GitHubSyncError catch (error) {
    stderr.writeln('Sync failed: $error');
    exitCode = 1;
  } finally {
    await repository.close();
    await dir.delete(recursive: true);
  }
}
