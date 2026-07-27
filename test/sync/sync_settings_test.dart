import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A keystore that is simply not there.
///
/// Stands in for a Linux box with no running secret service, which is a real
/// configuration — and the one where dropping the plaintext token before
/// confirming the secure write would lose it outright.
class _BrokenKeystore extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => throw Exception('no secret service');

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => throw Exception('no secret service');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw Exception('no secret service');

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => throw Exception('no secret service');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => throw Exception('no secret service');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => throw Exception('no secret service');
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('defaults', () {
    test(
      'points at the shared syncs repo with the baked-in client id',
      () async {
        final settings = await SyncSettings.load();

        expect(settings.owner, 'kuhyx');
        expect(settings.repo, 'syncs');
        expect(settings.token, isEmpty);
        expect(settings.clientId, SyncSettings.defaultClientId);
      },
    );

    // A device-flow client id is a public identifier, not a secret, which is
    // why it can be baked in and committed.
    test('the baked-in client id is non-empty', () {
      expect(SyncSettings.defaultClientId, isNotEmpty);
    });
  });

  group('isConfigured', () {
    test('needs owner, repo and token together', () {
      const complete = SyncSettings(owner: 'o', repo: 'r', token: 't');
      expect(complete.isConfigured, isTrue);

      expect(
        const SyncSettings(owner: '', repo: 'r', token: 't').isConfigured,
        isFalse,
      );
      expect(
        const SyncSettings(owner: 'o', repo: '', token: 't').isConfigured,
        isFalse,
      );
      expect(
        const SyncSettings(owner: 'o', repo: 'r', token: '').isConfigured,
        isFalse,
      );
    });
  });

  group('canUseDeviceFlow', () {
    test('is true only with a client id', () {
      expect(
        const SyncSettings(
          owner: 'o',
          repo: 'r',
          token: '',
          clientId: 'c',
        ).canUseDeviceFlow,
        isTrue,
      );
      expect(
        const SyncSettings(owner: 'o', repo: 'r', token: '').canUseDeviceFlow,
        isFalse,
      );
    });
  });

  group('save and load', () {
    test('round-trips every field', () async {
      const settings = SyncSettings(
        owner: 'someone',
        repo: 'their-repo',
        token: 'gho_secret',
        clientId: 'client-9',
      );

      await settings.save();
      final loaded = await SyncSettings.load();

      expect(loaded.owner, 'someone');
      expect(loaded.repo, 'their-repo');
      expect(loaded.token, 'gho_secret');
      expect(loaded.clientId, 'client-9');
    });

    // The token belongs in the OS keystore; SharedPreferences is plaintext.
    test('keeps the token out of shared preferences', () async {
      const settings = SyncSettings(
        owner: 'o',
        repo: 'r',
        token: 'gho_secret',
      );

      await settings.save();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync.token'), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'sync.token'),
        'gho_secret',
      );
    });

    test('clearing the token removes it from the keystore', () async {
      await const SyncSettings(owner: 'o', repo: 'r', token: 't').save();

      await const SyncSettings(owner: 'o', repo: 'r', token: '').save();

      expect(
        await const FlutterSecureStorage().read(key: 'sync.token'),
        isNull,
      );
      expect((await SyncSettings.load()).token, isEmpty);
    });

    // Older builds wrote the token to plaintext prefs. It is migrated on
    // read, and — importantly — the plaintext copy is only dropped once the
    // secure write is confirmed, so a device with no secret service degrades
    // to the old behaviour rather than losing the token.
    test('migrates a legacy plaintext token into the keystore', () async {
      SharedPreferences.setMockInitialValues({'sync.token': 'legacy'});

      final loaded = await SyncSettings.load();

      expect(loaded.token, 'legacy');
      expect(
        await const FlutterSecureStorage().read(key: 'sync.token'),
        'legacy',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync.token'), isNull);
    });

    test('prefers the keystore over a stale plaintext value', () async {
      SharedPreferences.setMockInitialValues({'sync.token': 'stale'});
      FlutterSecureStorage.setMockInitialValues({'sync.token': 'current'});

      expect((await SyncSettings.load()).token, 'current');
    });
  });

  // Degrading to the old plaintext behaviour is the point: a device with no
  // secret service must keep working, not lose its token.
  group('with no secret service available', () {
    setUp(() {
      FlutterSecureStoragePlatform.instance = _BrokenKeystore();
    });

    test('falls back to the plaintext token on read', () async {
      SharedPreferences.setMockInitialValues({'sync.token': 'legacy'});

      expect((await SyncSettings.load()).token, 'legacy');
    });

    test('keeps writing plaintext rather than dropping the token', () async {
      await const SyncSettings(owner: 'o', repo: 'r', token: 'tok').save();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync.token'), 'tok');
      expect((await SyncSettings.load()).token, 'tok');
    });
  });

  group('copyWith', () {
    test('replaces only what is named', () {
      const base = SyncSettings(
        owner: 'o',
        repo: 'r',
        token: 't',
        clientId: 'c',
      );

      expect(base.copyWith(owner: 'x').owner, 'x');
      expect(base.copyWith(owner: 'x').repo, 'r');
      expect(base.copyWith(repo: 'x').repo, 'x');
      expect(base.copyWith(token: 'x').token, 'x');
      expect(base.copyWith(clientId: 'x').clientId, 'x');
      expect(base.copyWith().token, 't');
    });
  });
}
