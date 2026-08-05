import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/sync/sync_state_factory_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a fresh install remembers nothing', () async {
    final store = await openSyncStateStore();

    final state = await store.load();

    expect(state.pushedRev, isNull);
    expect(state.peerRevs, isEmpty);
  });

  test('a saved revision survives a reopen', () async {
    final store = await openSyncStateStore();

    await store.save(
      const SyncState(pushedRev: 'abc', peerRevs: {'phone': 'def'}),
    );

    // A second store, as a cold start would build: the point of persisting
    // at all is that a fresh process does not re-download every peer.
    final reopened = await openSyncStateStore();
    final state = await reopened.load();

    expect(state.pushedRev, 'abc');
    expect(state.peerRevs, {'phone': 'def'});
  });

  test('writes under the documented key', () async {
    final store = await openSyncStateStore();

    await store.save(const SyncState(pushedRev: 'abc'));

    // Pinned because the key is the only thing tying a stored revision to the
    // log it describes: renaming it silently resets every device to "remember
    // nothing", which costs a full re-download rather than failing loudly.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kSyncStateKey);

    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as Map)['pushed_rev'], 'abc');
  });

  test('a corrupt entry degrades to remembering nothing', () async {
    SharedPreferences.setMockInitialValues({kSyncStateKey: 'not json'});
    final store = await openSyncStateStore();

    final state = await store.load();

    // Fail-safe, not fail-closed: one tick of extra traffic beats a sync that
    // cannot start because its cache is unreadable.
    expect(state.pushedRev, isNull);
    expect(state.peerRevs, isEmpty);
  });
}
