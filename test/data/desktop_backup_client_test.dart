import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/desktop_backup_client.dart';
import 'package:home_inventory/sync/desktop_wrapper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

void main() {
  // The origin is fixed on purpose: IndexedDB is keyed by it, so a changing
  // port would hide the whole local inventory behind an origin the user no
  // longer visits.
  test('defaults to the fixed wrapper origin', () {
    expect(desktopWrapperOrigin, 'http://localhost:$desktopWrapperPort');
    expect(desktopWrapperPort, 8733);
  });

  // Production constructs this with no arguments at all, so the defaulted
  // branch is the one that actually ships.
  test('defaults its http client and origin', () {
    final client = DesktopBackupClient();

    expect(client, isNotNull);
    client.close();
  });

  group('readLog', () {
    test('returns the stored body', () async {
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient(
          (_) async => http.Response('{"a":1}', 200),
        ),
      );
      addTearDown(client.close);

      expect(await client.readLog(), '{"a":1}');
    });

    test('returns null when the wrapper has nothing yet', () async {
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient(
          (_) async => http.Response('', 404),
        ),
      );
      addTearDown(client.close);

      expect(await client.readLog(), isNull);
    });

    test('returns null for an empty body', () async {
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient(
          (_) async => http.Response('', 200),
        ),
      );
      addTearDown(client.close);

      expect(await client.readLog(), isNull);
    });

    // A plain browser tab has no wrapper listening. That is a normal way to
    // run this build, not an error, so it must not throw.
    test('returns null when nothing is listening', () async {
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );
      addTearDown(client.close);

      expect(await client.readLog(), isNull);
    });
  });

  group('writeLog', () {
    test('posts the body to the backup endpoint', () async {
      String? seenPath;
      String? seenBody;
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient((request) async {
          seenPath = request.url.path;
          seenBody = request.body;
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);

      await client.writeLog('{"a":1}');

      expect(seenPath, '/backup/log');
      expect(seenBody, '{"a":1}');
    });

    test('swallows a failure — the mirror is best-effort', () async {
      final client = DesktopBackupClient(
        httpClient: http_testing.MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );
      addTearDown(client.close);

      await expectLater(client.writeLog('{}'), completes);
    });
  });

  test('honours an overridden origin', () async {
    Uri? seen;
    final client = DesktopBackupClient(
      origin: 'http://localhost:9999',
      httpClient: http_testing.MockClient((request) async {
        seen = request.url;
        return http.Response('x', 200);
      }),
    );
    addTearDown(client.close);

    await client.readLog();

    expect(seen.toString(), 'http://localhost:9999/backup/log');
  });
}
