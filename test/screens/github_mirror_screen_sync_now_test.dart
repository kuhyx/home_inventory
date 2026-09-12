import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/github_mirror_screen.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/builders.dart';
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

  Future<void> pumpMirror(
    WidgetTester tester,
    http.Client client, {
    Future<FirebaseRestClient?> Function()? firebaseFactory,
    Future<bool> Function()? sessionProbe,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      GitHubMirrorScreen(
        repository: repo,
        httpClient: client,
        now: () => at,
        // Injected so the widget never reaches for the platform: the real
        // factory wants an application-support directory, which does not
        // exist under `flutter test`.
        firebaseFactory: firebaseFactory ?? () async => null,
        sessionProbe: sessionProbe ?? () async => false,
        stateStore: InMemorySyncStateStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('syncs once configured and reports the count', (tester) async {
    await repo.upsert(itemFixture(name: 'Cable', updatedAt: at));
    final github = GitHubFake();
    await pumpMirror(tester, github.client);

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
    expect(github.puts.map((p) => p.path), [
      '$kSyncPathPrefix/me/$kSyncFileName',
      'inventory-sync/revs/me',
    ]);
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

    await pumpMirror(
      tester,
      github.client,
      firebaseFactory: () async => firebase,
    );
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
    await pumpMirror(tester, github.client);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    // A failed sync must never take the app down — it becomes a message.
    expect(find.textContaining('not found'), findsOneWidget);
  });
}
