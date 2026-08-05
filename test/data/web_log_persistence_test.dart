import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/desktop_backup_client.dart';
import 'package:home_inventory/data/web_log_persistence.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_client_memory.dart';

/// The desktop store, exercised against an in-memory IndexedDB.
///
/// `newIdbFactoryMemory()` rather than the `idbFactoryMemory` singleton: each
/// test needs its own database, or a leftover record from an earlier test
/// answers the "nothing stored yet" cases and they pass for the wrong reason.
void main() {
  late Database database;
  late List<String> mirrored;

  setUp(() async {
    database = await WebLogPersistence.openDatabase(newIdbFactoryMemory());
    mirrored = [];
  });

  tearDown(() {
    database.close();
  });

  /// A wrapper client that records what it was asked to mirror and answers
  /// reads with [onDisk].
  DesktopBackupClient backupClient({String? onDisk}) {
    final client = DesktopBackupClient(
      httpClient: http_testing.MockClient((request) async {
        if (request.method == 'POST') {
          mirrored.add(request.body);
          return http.Response('', 200);
        }
        return http.Response(onDisk ?? '', onDisk == null ? 404 : 200);
      }),
    );
    addTearDown(client.close);
    return client;
  }

  WebLogPersistence persistence({
    DesktopBackupClient? backup,
    Duration debounce = const Duration(milliseconds: 20),
  }) {
    final store = WebLogPersistence(
      database: database,
      backup: backup,
      mirrorDebounce: debounce,
    );
    addTearDown(store.dispose);
    return store;
  }

  /// Waits past the debounce, so a mirror that was going to fire has fired.
  Future<void> settleMirror() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  group('read', () {
    test('returns null on a fresh profile with no wrapper', () async {
      expect(await persistence().read(), isNull);
    });

    test('returns what was written', () async {
      final store = persistence();

      await store.write('{"a":1}');

      expect(await store.read(), '{"a":1}');
    });

    test('survives a new store over the same database', () async {
      await persistence().write('{"a":1}');

      expect(await persistence().read(), '{"a":1}');
    });

    // The reason the wrapper exists: Chrome evicting the origin's storage, or
    // the user wiping the profile, would otherwise be a total-loss event for
    // anything not yet synced to GitHub.
    test('falls back to the on-disk copy when IndexedDB is empty', () async {
      final store = persistence(backup: backupClient(onDisk: '{"disk":1}'));

      expect(await store.read(), '{"disk":1}');
    });

    test('falls back when the stored value is blank', () async {
      final store = persistence(backup: backupClient(onDisk: '{"disk":1}'));

      await store.write('');

      expect(await store.read(), '{"disk":1}');
    });

    test('prefers IndexedDB over the on-disk copy', () async {
      final store = persistence(backup: backupClient(onDisk: '{"disk":1}'));

      await store.write('{"local":1}');

      expect(await store.read(), '{"local":1}');
    });

    test('returns null when the wrapper has nothing either', () async {
      final store = persistence(backup: backupClient());

      expect(await store.read(), isNull);
    });
  });

  group('mirroring', () {
    test('pushes the log to the wrapper after the debounce', () async {
      final store = persistence(backup: backupClient());

      await store.write('{"a":1}');
      expect(mirrored, isEmpty, reason: 'must not fire before the debounce');
      await settleMirror();

      expect(mirrored, ['{"a":1}']);
    });

    // A single quantity tap writes twice (the item, then its adjustment), so
    // an eager mirror would mean an HTTP request and a whole-log disk write
    // per keystroke during bulk entry.
    test('coalesces a burst into one push of the final text', () async {
      final store = persistence(backup: backupClient());

      await store.write('{"a":1}');
      await store.write('{"a":2}');
      await store.write('{"a":3}');
      await settleMirror();

      expect(mirrored, ['{"a":3}']);
    });

    test('dispose cancels a mirror that has not fired yet', () async {
      final store = persistence(backup: backupClient());

      await store.write('{"a":1}');
      store.dispose();
      await settleMirror();

      expect(mirrored, isEmpty);
    });

    // The same web build opened in a plain browser tab has no wrapper at all;
    // writing must stay a normal, silent success there.
    test('writes fine with no wrapper configured', () async {
      final store = persistence();

      await store.write('{"a":1}');
      await settleMirror();

      expect(await store.read(), '{"a":1}');
      expect(mirrored, isEmpty);
    });
  });
}
