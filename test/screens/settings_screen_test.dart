import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/builders.dart';
import '../support/file_selector_fake.dart';
import '../support/github_fake.dart';
import '../support/pump.dart';

/// Records launches instead of opening a browser.
///
/// Faked through the platform interface rather than `coverage:ignore`d, so
/// the connect flow's real code path is exercised.
class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

/// A launcher that refuses, standing in for a device with no browser.
class _BrokenLauncher extends _FakeLauncher {
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async =>
      throw Exception('no browser');
}

void main() {
  final at = DateTime.utc(2026, 7, 26);

  late ItemRepository repo;
  late _FakeLauncher launcher;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    repo = await ItemRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async {
    await repo.close();
  });

  Future<void> pumpSettings(
    WidgetTester tester,
    http.Client client, {
    Future<FirebaseRestClient?> Function()? firebaseFactory,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      SettingsScreen(
        repository: repo,
        httpClient: client,
        now: () => at,
        // Both injected so the widget never reaches for the platform: the
        // real factories want an application-support directory and the OS
        // keystore, neither of which exists under `flutter test`.
        firebaseFactory: firebaseFactory ?? () async => null,
        stateStore: InMemorySyncStateStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the defaults and this device id', (tester) async {
    await pumpSettings(tester, GitHubFake().client);

    expect(find.text('kuhyx'), findsOneWidget);
    expect(find.text('syncs'), findsOneWidget);
    expect(find.text('This device: me'), findsOneWidget);
  });

  testWidgets('reports a reachable repo', (tester) async {
    await pumpSettings(tester, GitHubFake().client);

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected to kuhyx/syncs.'), findsOneWidget);
  });

  testWidgets('reports an unreachable repo without throwing', (tester) async {
    await pumpSettings(tester, GitHubFake(repoExists: false).client);

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach kuhyx/syncs.'), findsOneWidget);
  });

  testWidgets('refuses to sync before a token exists', (tester) async {
    await pumpSettings(tester, GitHubFake().client);

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(find.text('Connect GitHub first.'), findsOneWidget);
  });

  testWidgets('a pasted token is saved to the keystore', (tester) async {
    await pumpSettings(tester, GitHubFake().client);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();

    expect(find.text('Token saved.'), findsOneWidget);
    expect((await SyncSettings.load()).token, 'gho_pasted');
  });

  testWidgets('an empty pasted token does nothing', (tester) async {
    await pumpSettings(tester, GitHubFake().client);

    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();

    expect(find.text('Token saved.'), findsNothing);
  });

  testWidgets('syncs once configured and reports the count', (tester) async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: at));
    final github = GitHubFake();
    await pumpSettings(tester, github.client);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(find.text('Synced via GitHub — 1 item.'), findsOneWidget);
    // Two writes now: the log, then this device's revision. The revision is
    // what lets a later tick skip re-downloading an unchanged peer, and it is
    // published *after* the log so a peer can never cache "seen rev X"
    // against a log it never received.
    expect(
      github.puts.map((p) => p.path),
      ['$kSyncPathPrefix/me/$kSyncFileName', 'inventory-sync/revs/me'],
    );
  });

  testWidgets('syncs via Firebase and still mirrors to GitHub', (tester) async {
    // The cutover guarantee: Firebase is authoritative, and GitHub keeps
    // receiving the same writes so an un-migrated device still converges.
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: at));
    final github = GitHubFake();
    final firebasePuts = <String>[];
    final firebase = FirebaseRestClient(
      databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
      auth: FirebaseTokenProvider(
        apiKey: 'AIzaKey',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'refresh',
            // Real wall clock, not the fixed test `at`: the token provider
            // compares against DateTime.now(), so a session dated from the
            // fixture's past looks expired and triggers a refresh.
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
      httpClient: http_testing.MockClient((request) async {
        if (request.method == 'PUT') {
          firebasePuts.add(request.url.path);
          return http.Response(request.body, 200);
        }
        // Nothing stored yet: an empty database answers `null`.
        return http.Response('null', 200);
      }),
    );

    await pumpSettings(tester, github.client, firebaseFactory: () async => firebase);
    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(find.text('Synced via Firebase — 1 item.'), findsOneWidget);
    expect(
      firebasePuts.any((p) => p.contains('inventory-sync')),
      isTrue,
      reason: 'Firebase is the primary and must receive the write',
    );
    expect(
      github.puts,
      isNotEmpty,
      reason: 'GitHub must still be mirrored during the cutover',
    );
  });

  testWidgets('surfaces a sync failure as a status line', (tester) async {
    final github = GitHubFake(repoExists: false);
    await pumpSettings(tester, github.client);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    // A failed sync must never take the app down — it becomes a message.
    expect(find.textContaining('not found'), findsOneWidget);
  });

  // Not every failure is a GitHubSyncError: a dead network surfaces as an
  // http ClientException, and that must still become a status line rather
  // than an unhandled exception in a button callback.
  testWidgets('reports a transport failure without crashing', (tester) async {
    final dead = http_testing.MockClient(
      (_) async => throw http.ClientException('network is down'),
    );
    await pumpSettings(tester, dead);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('network is down'), findsOneWidget);
  });

  group('device flow', () {
    http.Client authClient({String? token, String? error}) =>
        http_testing.MockClient((request) async {
          if (request.url.path.contains('/login/device/code')) {
            return http.Response(
              jsonEncode({
                'device_code': 'dev-1',
                'user_code': 'ABCD-1234',
                'verification_uri': 'https://github.com/login/device',
                'interval': 0,
                'expires_in': 900,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(
              token != null
                  ? {'access_token': token}
                  : {'error': error, 'error_description': 'declined'},
            ),
            200,
          );
        });

    testWidgets('shows the user code and stores the minted token', (
      tester,
    ) async {
      await pumpSettings(tester, authClient(token: 'gho_from_flow'));

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ABCD-1234'), findsNothing);
      expect(find.text('Connected to GitHub.'), findsOneWidget);
      expect((await SyncSettings.load()).token, 'gho_from_flow');
      expect(launcher.launched, ['https://github.com/login/device']);
    });

    testWidgets('reports a declined authorization', (tester) async {
      await pumpSettings(tester, authClient(error: 'access_denied'));

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('declined'), findsOneWidget);
      expect((await SyncSettings.load()).token, isEmpty);
    });

    // A machine with no browser can still complete the flow by typing the
    // URL that is already on screen, so a launch failure must not abort it.
    testWidgets('a browser that will not open still completes the flow', (
      tester,
    ) async {
      UrlLauncherPlatform.instance = _BrokenLauncher();
      await pumpSettings(tester, authClient(token: 'gho_from_flow'));

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('Connected to GitHub.'), findsOneWidget);
      expect((await SyncSettings.load()).token, 'gho_from_flow');
    });

    testWidgets('refuses when no client id is configured', (tester) async {
      SharedPreferences.setMockInitialValues({'sync.clientId': ''});
      await pumpSettings(tester, GitHubFake().client);

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('No client id configured.'), findsOneWidget);
    });
  });

  group('backup file', () {
    late FakeFileSelector selector;
    late Directory temp;

    setUp(() async {
      selector = FakeFileSelector();
      FileSelectorPlatform.instance = selector;
      temp = await Directory.systemTemp.createTemp('home_inventory_settings');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    /// Taps [label] and lets the real filesystem work finish.
    ///
    /// `flutter_test` runs inside a fake-async zone where `dart:io` futures
    /// never complete, so a plain `pumpAndSettle` here asserts against a file
    /// that has been created but not yet written. `runAsync` turns the real
    /// event loop; the pump afterwards is what renders the status line.
    Future<void> tapAndFlush(WidgetTester tester, String label) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('exports the whole log to a chosen file', (tester) async {
      await repo.upsert(itemFixture(id: 'a', name: 'Cable'));
      final path = '${temp.path}/backup.json';
      selector.saveLocation = FileSaveLocation(path);
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Export inventory');

      expect(File(path).readAsStringSync(), contains('Cable'));
      // Singular. '1 items' shipped once already; see commit 6d0df13.
      expect(find.textContaining('Exported 1 item to'), findsOneWidget);
    });

    testWidgets('a cancelled export says so', (tester) async {
      selector.saveLocation = null;
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Export inventory');

      expect(find.text('Export cancelled.'), findsOneWidget);
    });

    testWidgets('imports a backup and reports the new count', (tester) async {
      final source = await ItemRepository.openInMemory(nodeId: 'other');
      addTearDown(source.close);
      await source.upsert(itemFixture(id: 'a', name: 'Cable'));
      final path = '${temp.path}/backup.json';
      File(path).writeAsStringSync(source.exportJson());
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Import inventory');

      expect(repo.item('a')!.name, 'Cable');
      expect(find.text('Imported — 1 item now.'), findsOneWidget);
    });

    testWidgets('a cancelled import says so', (tester) async {
      selector.fileToOpen = null;
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Import inventory');

      expect(find.text('Import cancelled.'), findsOneWidget);
    });

    // Picking the wrong file is ordinary user input. The decoder throws a
    // TypeError (an Error, not an Exception) on JSON of the wrong shape, which
    // the screen's generic guard would let escape.
    testWidgets('the wrong file is reported, not thrown', (tester) async {
      final path = '${temp.path}/wrong.json';
      File(path).writeAsStringSync('[1, 2, 3]');
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Import inventory');

      expect(
        find.textContaining('not an inventory backup'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file that is not JSON at all is reported too', (
      tester,
    ) async {
      final path = '${temp.path}/notes.txt';
      File(path).writeAsStringSync('shopping list');
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Import inventory');

      expect(
        find.textContaining('not an inventory backup'),
        findsOneWidget,
      );
    });

    testWidgets('a plural count reads correctly', (tester) async {
      final source = await ItemRepository.openInMemory(nodeId: 'other');
      addTearDown(source.close);
      await source.upsert(itemFixture(id: 'a', name: 'Cable'));
      await source.upsert(itemFixture(id: 'b', name: 'Flour'));
      final path = '${temp.path}/backup.json';
      File(path).writeAsStringSync(source.exportJson());
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester, GitHubFake().client);

      await tapAndFlush(tester, 'Import inventory');

      expect(find.text('Imported — 2 items now.'), findsOneWidget);
    });
  });
}
