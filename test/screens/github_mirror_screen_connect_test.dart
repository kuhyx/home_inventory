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

  testWidgets('shows the defaults and this device id', (tester) async {
    await pumpMirror(tester, GitHubFake().client);

    expect(find.text('kuhyx'), findsOneWidget);
    expect(find.text('syncs'), findsOneWidget);
    expect(find.text('This device: me'), findsOneWidget);
  });
  testWidgets('reports a reachable repo', (tester) async {
    await pumpMirror(tester, GitHubFake().client);

    await tester.tap(find.text('Test GitHub connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected to kuhyx/syncs.'), findsOneWidget);
  });
  testWidgets('reports an unreachable repo without throwing', (tester) async {
    await pumpMirror(tester, GitHubFake(repoExists: false).client);

    await tester.tap(find.text('Test GitHub connection'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach kuhyx/syncs.'), findsOneWidget);
  });
  testWidgets('refuses to sync before a token exists', (tester) async {
    await pumpMirror(tester, GitHubFake().client);

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Connect a sync backend in Settings first.'),
      findsOneWidget,
    );
  });
  testWidgets('a Firebase-connected device is not asked to connect a backend', (
    tester,
  ) async {
    // Neither settings.isConfigured nor a GitHub token is set, but the
    // session probe reports a live Firebase session -- syncing must be
    // offered anyway, since gating on the GitHub token alone would lock a
    // Firebase-only device out entirely.
    final firebasePuts = <String>[];
    final firebase = FirebaseRestClient(
      databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
      auth: FirebaseTokenProvider(
        apiKey: 'AIzaKey',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
      httpClient: http_testing.MockClient((request) async {
        if (request.method == 'PUT') {
          firebasePuts.add(request.url.path);
          return http.Response(request.body, 200);
        }
        return http.Response('null', 200);
      }),
    );
    await pumpMirror(
      tester,
      GitHubFake().client,
      firebaseFactory: () async => firebase,
      sessionProbe: () async => true,
    );

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Connect a sync backend in Settings first.'),
      findsNothing,
    );
    expect(
      firebasePuts.any((p) => p.contains('inventory-sync')),
      isTrue,
      reason: 'Firebase is the primary and must receive the write',
    );
  });
  testWidgets('a pasted token is saved to the keystore', (tester) async {
    await pumpMirror(tester, GitHubFake().client);

    await tester.enterText(find.byType(TextField).last, 'gho_pasted');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();

    expect(find.text('Token saved.'), findsOneWidget);
    expect((await SyncSettings.load()).token, 'gho_pasted');
  });
  testWidgets('an empty pasted token does nothing', (tester) async {
    await pumpMirror(tester, GitHubFake().client);

    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();

    expect(find.text('Token saved.'), findsNothing);
  });
}
