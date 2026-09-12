/// The two network actions the GitHub mirror screen offers.
///
/// Separated from the screen so the transport decisions — which backend is
/// primary, what counts as "configured" — can be read without wading through
/// widget state, and so the screen is left holding only its form.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:http/http.dart' as http;

/// Checks that the configured repo is reachable, as a status line.
Future<String> testGitHubConnection(
  SyncSettings settings, {
  http.Client? httpClient,
}) async {
  final client = GitHubClient(
    owner: settings.owner,
    repo: settings.repo,
    token: settings.token,
    httpClient: httpClient,
  );
  try {
    final ok = await client.canAccessRepo();
    return ok
        ? 'Connected to ${settings.owner}/${settings.repo}.'
        : 'Cannot reach ${settings.owner}/${settings.repo}.';
  } finally {
    client.close();
  }
}

/// Runs one sync, preferring Firebase and falling back to the mirror.
///
/// Firebase is the primary backend when this device has been set up for it;
/// GitHub stays as a mirror until every device has moved. Not being set up is
/// a normal state, not an error — the app keeps syncing over GitHub exactly
/// as before.
Future<String> runMirrorSync({
  required ItemRepository repository,
  required SyncSettings settings,
  required Future<FirebaseRestClient?> Function() firebaseFactory,
  required SyncStateStore stateStore,
  http.Client? httpClient,
  DateTime? now,
}) async {
  final firebase = await firebaseFactory();
  try {
    final outcome = await SyncService(repository).sync(
      owner: settings.owner,
      repo: settings.repo,
      token: settings.token,
      firebase: firebase,
      stateStore: stateStore,
      httpClient: httpClient,
      now: now,
    );
    final n = outcome.itemCount;
    final via = firebase == null ? 'GitHub' : 'Firebase';
    return 'Synced via $via — $n ${n == 1 ? 'item' : 'items'}.';
  } finally {
    firebase?.close();
  }
}
