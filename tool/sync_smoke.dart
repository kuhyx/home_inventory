// A manual, against-real-GitHub check that sync actually works.
//
// Deliberately outside `lib/`: this is a plain Dart CLI, so `dart:io` is fine
// here and would not be inside the app's graph. It is not part of the test
// suite — it talks to the network.
//
// Usage, from the repo root:
//
//   GITHUB_TOKEN=<pat> dart run tool/sync_smoke.dart
//   GITHUB_TOKEN=<pat> dart run tool/sync_smoke.dart --seed "Test cable"
//
// Pass --seed to push one throwaway item; run it again without --seed (which
// gets a fresh node id) and that item should come back. That two-run pair is
// what actually proves a round trip — a bare run only proves the push half.
//
// `--dir` turns this into a *persistent* peer instead: a stable node id and a
// store that survives between runs, which is what the convergence checks need.
// One-shot runs cannot express "edit, then sync later", and that gap is
// exactly where per-field LWW either works or silently does not:
//
//   # reverse direction (PC -> phone)
//   ... --dir /tmp/peer --seed "Sync check"
//   # then tap Sync on the phone; the item should appear
//
//   # concurrent edits: change different fields on each side BEFORE syncing
//   ... --dir /tmp/peer --set <id> room Workshop --no-sync
//   # change the quantity on the phone, then sync both. Both must survive.
//
//   # clean up
//   ... --dir /tmp/peer --delete <id>
//
// A stable node id writes a stable file in the syncs repo, so a peer directory
// you are finished with leaves a slot behind; `--forget` deletes that file from
// GitHub, which a throwaway run cannot do for itself.
//
// It reads the token from the environment rather than the app's keystore
// because a CLI has no secure storage; a fine-grained PAT with contents
// read/write on kuhyx/syncs is enough.

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final token = Platform.environment['GITHUB_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('Set GITHUB_TOKEN to a PAT with contents access.');
    exitCode = 2;
    return;
  }

  final owner = Platform.environment['SYNC_OWNER'] ?? 'kuhyx';
  final repo = Platform.environment['SYNC_REPO'] ?? 'syncs';

  final peerDir = _value(args, '--dir');
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

  final forget = _value(args, '--forget');
  if (forget != null) {
    await _forgetPeer(
      owner: owner,
      repo: repo,
      token: token,
      deviceId: forget,
    );
    return;
  }

  final repository = await ItemRepository.openWith(
    persistence: FileLogPersistence(
      File(p.join(directory.path, ItemRepository.logFileName)),
    ),
    nodeId: nodeId,
  );

  try {
    await _applyEdits(args, repository);

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
Future<void> _applyEdits(List<String> args, ItemRepository repository) async {
  final seed = _value(args, '--seed');
  if (seed != null) {
    final at = DateTime.now();
    await repository.upsert(
      Item(
        id: 'smoke-${at.millisecondsSinceEpoch}',
        name: seed,
        quantity: 3,
        unit: '',
        room: 'Smoke test',
        container: 'Throwaway',
        category: '',
        lowStockAt: null,
        wanted: false,
        sellable: false,
        notes: 'written by tool/sync_smoke.dart',
        createdAt: at,
        updatedAt: at,
      ),
    );
    stdout.writeln('Seeded "$seed".');
  }

  final delete = _value(args, '--delete');
  if (delete != null) {
    await repository.delete(delete);
    stdout.writeln('Deleted $delete.');
  }

  final setIndex = args.indexOf('--set');
  if (setIndex == -1) return;
  if (setIndex + 3 >= args.length) {
    stderr.writeln('--set needs <id> <field> <value>.');
    exitCode = 2;
    return;
  }
  final id = args[setIndex + 1];
  final field = args[setIndex + 2];
  final value = args[setIndex + 3];
  final current = repository.item(id);
  if (current == null) {
    stderr.writeln('No item $id here. Sync first, or check --list output.');
    exitCode = 2;
    return;
  }
  await _setField(repository, current, field, value);
}

Future<void> _setField(
  ItemRepository repository,
  Item current,
  String field,
  String value,
) async {
  // Quantity goes through adjustQuantity rather than upsert so the change is
  // attributed explicitly. A silent default here is how a recount gets
  // recorded as consumption and quadruples the burn rate.
  if (field == 'quantity') {
    final wanted = double.tryParse(value);
    if (wanted == null) {
      stderr.writeln('quantity must be a number.');
      exitCode = 2;
      return;
    }
    await repository.setQuantity(
      current.id,
      wanted,
      AdjustmentSource.correction,
    );
    stdout.writeln('Set quantity of ${current.name} to $value.');
    return;
  }

  final updated = switch (field) {
    'name' => current.copyWith(name: value, updatedAt: DateTime.now()),
    'room' => current.copyWith(room: value, updatedAt: DateTime.now()),
    'container' => current.copyWith(
      container: value,
      updatedAt: DateTime.now(),
    ),
    'notes' => current.copyWith(notes: value, updatedAt: DateTime.now()),
    _ => null,
  };
  if (updated == null) {
    stderr.writeln(
      'Unknown field "$field" — try name, room, container, notes or quantity.',
    );
    exitCode = 2;
    return;
  }
  await repository.upsert(updated);
  stdout.writeln('Set $field of ${current.name} to "$value".');
}

void _report(ItemRepository repository) {
  for (final item in repository.listItems()) {
    final where = item.location.isEmpty ? 'nowhere recorded' : item.location;
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
    await client.deleteFile(
      path,
      message: 'home_inventory: forget $deviceId',
    );
    stdout.writeln('Deleted $path.');
  } on GitHubSyncError catch (error) {
    stderr.writeln('Could not delete $path: $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}

String? _value(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
