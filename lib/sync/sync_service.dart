/// Peer-to-peer sync over a GitHub repo used as dumb file storage.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:http/http.dart' as http;

/// Where each device's log file lives inside the shared `syncs` repo.
///
/// One file per device, so two devices never write the same path and there
/// are no git-level conflicts to resolve — convergence is the CRDT's job.
const String kSyncPathPrefix = 'inventory-sync/devices';

/// File name each device writes under its own directory.
const String kSyncFileName = 'inventory.json';

/// What one sync tick did, for the settings screen to report.
class SyncOutcome {
  /// Creates an outcome.
  const SyncOutcome({required this.itemCount, required this.pushed});

  /// How many live items exist after the merge.
  final int itemCount;

  /// Whether this device's file was written.
  final bool pushed;
}

/// Runs one pull-merge-push tick against GitHub.
///
/// Thin on purpose: `syncLog` does the transport and the merge, and the CRDT
/// does conflict resolution, so the only real decisions here are the paths and
/// the encode/decode pair.
///
/// Takes the three credential fields rather than a `SyncSettings`, so this
/// layer stays free of how settings are *stored*. `SyncSettings` reaches for
/// `flutter_secure_storage`, which drags in all of Flutter — depending on it
/// here would make `tool/sync_smoke.dart` unrunnable under plain `dart run`.
class SyncService {
  /// Creates a service over [repository].
  const SyncService(this.repository);

  /// Store whose log is synced.
  final ItemRepository repository;

  /// Pulls every peer's log, merges, and pushes this device's result.
  ///
  /// When [firebase] is given it becomes the **primary** backend and GitHub
  /// is kept as a mirror: Firebase failures fail the tick, GitHub failures are
  /// logged and tolerated, and reads union both. That is what lets the PC and
  /// the phone cut over on different days without either losing sight of the
  /// other. Passing null is the pre-migration behaviour, and is also the
  /// rollback: one argument, no data movement.
  ///
  /// [stateStore] carries the revision cache between runs. Without it every
  /// tick re-downloads every peer's whole log regardless of whether anything
  /// changed — the traffic that the free tier's 10 GB/month budget depends on
  /// not happening. It is optional only so the smoke tool can opt out.
  ///
  /// Throws [GitHubSyncError] (including [RepoNotFoundError]) when GitHub
  /// rejects the request; callers surface that rather than crashing.
  Future<SyncOutcome> sync({
    required String owner,
    required String repo,
    required String token,
    RemoteStore? firebase,
    SyncStateStore? stateStore,
    http.Client? httpClient,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final github = GitHubClient(
      owner: owner,
      repo: repo,
      token: token,
      httpClient: httpClient,
    );
    final client = firebase == null
        ? github
        : MirrorStore(primary: firebase, mirror: github);
    try {
      final merged = await syncLog(
        client: client,
        deviceId: repository.nodeId,
        pathPrefix: kSyncPathPrefix,
        localLog: repository.exportLog(),
        stateStore: stateStore,
        encode: logToJson,
        // The prune MUST happen here, not only on load. `syncLog` pushes the
        // merge of the local log with every peer file, so pruning locally
        // alone lets a peer's stale file re-introduce an aged-out record,
        // which is then pushed straight back — a commit on every sync,
        // forever, with the log never shrinking. Filtering inside `decode`
        // means an ancient record cannot re-enter the merge from any source.
        decode: (text) => dropAncientAdjustments(logFromJson(text), at),
        filename: kSyncFileName,
        commitMessage: 'home_inventory sync',
      );
      await repository.replaceAll(merged);
      return SyncOutcome(
        itemCount: repository.listItems().length,
        pushed: true,
      );
    } finally {
      // Close the GitHub client specifically: MirrorStore.close() would also
      // close the Firebase client, which the caller owns and reuses across
      // ticks so the cached session survives.
      github.close();
    }
  }
}
