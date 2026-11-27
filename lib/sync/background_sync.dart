/// The tick [AutoSync] runs in production: the same sync as the mirror
/// screen's "Sync now", but silent and never throwing.
library;

import 'dart:developer';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/auto_sync.dart';
import 'package:home_inventory/sync/firebase_backend.dart';
import 'package:home_inventory/sync/github_mirror_actions.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:home_inventory/sync/sync_state_factory.dart';
import 'package:http/http.dart' as http;

/// Runs one background sync of [repository].
///
/// Skipped when neither backend is set up (a fresh install is not an error)
/// and when the passphrase is missing ([e2eLocked] already shows that).
/// Any other failure is logged and reported as [AutoSyncResult.failed], so
/// the scheduler retries; the local log is never touched by a failed tick.
///
/// The defaults are the real platform backends; tests inject fakes.
Future<AutoSyncResult> runBackgroundSync(
  ItemRepository repository, {
  Future<FirebaseRestClient?> Function() firebaseFactory = openFirebase,
  Future<bool> Function() sessionProbe = isFirebaseConfigured,
  Future<SyncStateStore> Function() stateStore = openSyncStateStore,
  http.Client? httpClient,
}) async {
  try {
    final settings = await SyncSettings.load();
    // Either backend counts, as for "Sync now": a Firebase-only device has
    // no GitHub token and must still sync.
    if (!settings.isConfigured && !await sessionProbe()) {
      return AutoSyncResult.skipped;
    }
    final outcome = await runMirrorSync(
      repository: repository,
      settings: settings,
      firebaseFactory: firebaseFactory,
      stateStore: await stateStore(),
      httpClient: httpClient,
    );
    // runMirrorSync reports not-ok only for a locked (passphrase-less) run.
    return outcome.ok ? AutoSyncResult.synced : AutoSyncResult.skipped;
  } on Exception catch (error) {
    log('background sync failed: $error', name: 'home_inventory.sync');
    return AutoSyncResult.failed;
  }
}
