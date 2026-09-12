// A manual, against-real-GitHub check that sync actually works.
//
// Usage and the convergence recipes: tool/DOCS-sync-smoke.md.
//
// Deliberately outside `lib/`: this is a plain Dart CLI, so `dart:io` is fine
// here and would not be inside the app's graph. It is not part of the test
// suite — it talks to the network.
//
// It reads the token from the environment rather than the app's keystore
// because a CLI has no secure storage; a fine-grained PAT with contents
// read/write on kuhyx/syncs is enough.

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:path/path.dart' as p;

import 'sync_smoke_edits.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['GITHUB_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('Set GITHUB_TOKEN to a PAT with contents access.');
    exitCode = 2;
    return;
  }

  final owner = Platform.environment['SYNC_OWNER'] ?? 'kuhyx';
  final repo = Platform.environment['SYNC_REPO'] ?? 'syncs';

  final peerDir = argValue(args, '--dir');
  // A --dir run pushes under a *stable* id, so unlike a bare run it lands in
  // a real device slot that persists. Pointed at the live repo that means
  // permanent test data in production: a `--dir peer-pc` run once wrote
  // HLC stamps signed `peer-peer-pc` into the real inventory-sync namespace,
  // where they are indistinguishable from a genuine device's. Require an
  // explicit opt-in rather than trusting whoever runs this to remember.
  if (peerDir != null &&
      owner == 'kuhyx' &&
      repo == 'syncs' &&
      Platform.environment['SYNC_SMOKE_ALLOW_LIVE'] != '1') {
    stderr.writeln(
      'Refusing to run a --dir smoke test against the live $owner/$repo.\n'
      'A stable peer id writes a permanent device slot there. Either:\n'
      '  - point it elsewhere: SYNC_OWNER=<you> SYNC_REPO=<scratch-repo>\n'
      '  - drop --dir, which uses a throwaway id and directory, or\n'
      '  - if you really mean it: SYNC_SMOKE_ALLOW_LIVE=1 (then clean up\n'
      '    afterwards with --forget <id>).',
    );
    exitCode = 2;
    return;
  }
  // Without --dir: a throwaway node id and a throwaway directory, so a bare
  // run can never write into a real device's slot and clobber that device's
  // file. With --dir: a stable id, because a peer that forgets who it is
  // cannot demonstrate convergence — it just looks like a new device.
  final directory = peerDir == null
      ? await Directory.systemTemp.createTemp('inventory-smoke')
      : (Directory(peerDir)..createSync(recursive: true));
  final nodeId = peerDir == null
      ? 'smoke-${DateTime.now().millisecondsSinceEpoch}'
      : _stableNodeId(directory);

  final forget = argValue(args, '--forget');
  if (forget != null) {
    await _forgetPeer(owner: owner, repo: repo, token: token, deviceId: forget);
    return;
  }

  final repository = await ItemRepository.openWith(
    persistence: FileLogPersistence(
      File(p.join(directory.path, ItemRepository.logFileName)),
    ),
    nodeId: nodeId,
  );

  try {
    await applyEdits(args, repository);

    if (args.contains('--no-sync')) {
      stdout.writeln('Local edit only — not synced (as asked).');
      _report(repository);
      return;
    }

    stdout.writeln('Syncing as ${repository.nodeId} against $owner/$repo …');
    final outcome = await SyncService(
      repository,
    ).sync(owner: owner, repo: repo, token: token);
    stdout.writeln('Merged ${outcome.itemCount} items.');
    _report(repository);
    if (outcome.itemCount == 0) {
      stdout.writeln('Nothing found — has a device pushed yet?');
    }
  } on GitHubSyncError catch (error) {
    stderr.writeln('Sync failed: $error');
    exitCode = 1;
  } finally {
    await repository.close();
    // Only a throwaway directory is ours to remove; a peer directory is the
    // caller's, and deleting it would silently reset the peer's identity.
    if (peerDir == null) await directory.delete(recursive: true);
  }
}

/// Applies whatever mutations the arguments asked for, before any sync.
void _report(ItemRepository repository) {
  for (final item in repository.listItems()) {
    final where = item.locationId.isEmpty
        ? (item.legacyLocation.isEmpty
              ? 'nowhere recorded'
              : item.legacyLocation)
        : repository.pathLabel(item.locationId);
    stdout.writeln(
      '  ${item.id}  ${item.name}  '
      '×${formatQuantity(item.quantity)}  ($where)',
    );
  }
}

/// Reads (or creates) this peer directory's stable node id.
String _stableNodeId(Directory directory) {
  final file = File(p.join(directory.path, '.node_id'));
  if (file.existsSync()) return file.readAsStringSync().trim();
  final id = 'peer-${p.basename(directory.path)}';
  file.writeAsStringSync(id);
  return id;
}

/// Deletes a device's file from the sync repo, so a finished peer stops being
/// merged into every future sync forever.
Future<void> _forgetPeer({
  required String owner,
  required String repo,
  required String token,
  required String deviceId,
}) async {
  final client = GitHubClient(owner: owner, repo: repo, token: token);
  final path = '$kSyncPathPrefix/$deviceId/$kSyncFileName';
  try {
    await client.deleteFile(path, message: 'home_inventory: forget $deviceId');
    stdout.writeln('Deleted $path.');
  } on GitHubSyncError catch (error) {
    stderr.writeln('Could not delete $path: $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}
