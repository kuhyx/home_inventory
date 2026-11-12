/// The two network actions the GitHub mirror screen offers.
///
/// Separated from the screen so the transport decisions — which backend is
/// primary, what counts as "configured" — can be read without wading through
/// widget state, and so the screen is left holding only its form.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey, kSecureStorage, keystoreKeyCache;
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:http/http.dart' as http;

/// Argon2id cost for new end-to-end headers; only tests lower it.
@visibleForTesting
Argon2Params e2eArgon2Params = Argon2Params.recommended;

/// Whether the last sync found no usable end-to-end key; drives the lock
/// button on the mirror screen.
final ValueNotifier<bool> e2eLocked = ValueNotifier<bool>(false);

/// The result of a mirror action: whether it worked, and a spoken-only line.
typedef MirrorOutcome = ({bool ok, String spoken});

/// Checks that the configured repo is reachable.
Future<MirrorOutcome> testGitHubConnection(
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
    final where = '${settings.owner}/${settings.repo}';
    return (
      ok: ok,
      spoken: ok ? 'Connected to $where.' : 'Cannot reach $where.',
    );
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
///
/// Pushes are end-to-end encrypted under the passphrase in the OS keystore;
/// with none (or a wrong one) the run does nothing, reports not-ok, and sets
/// [e2eLocked].
Future<MirrorOutcome> runMirrorSync({
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
      readPassphrase: () => kSecureStorage.read(key: kE2ePassphraseKey),
      // Argon2id once per device, not once per tick.
      keyCache: keystoreKeyCache(kSyncPathPrefix),
      e2eParams: e2eArgon2Params,
      firebase: firebase,
      stateStore: stateStore,
      httpClient: httpClient,
      now: now,
    );
    e2eLocked.value = outcome.locked;
    if (outcome.locked) {
      return (ok: false, spoken: 'Sync locked: enter the sync passphrase.');
    }
    final n = outcome.itemCount;
    final via = firebase == null ? 'GitHub' : 'Firebase';
    return (
      ok: true,
      spoken: 'Synced via $via — $n ${n == 1 ? 'item' : 'items'}.',
    );
  } finally {
    firebase?.close();
  }
}
