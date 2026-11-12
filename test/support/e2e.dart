import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/sync/github_mirror_actions.dart';

/// Argon2id cheap enough for tests; production keeps the recommended cost.
const Argon2Params testArgon2 = Argon2Params(
  memoryKiB: 8,
  iterations: 1,
  parallelism: 1,
);

/// The shared crdt-sync passphrase every syncing test unlocks with.
const String testPassphrase = 'test-passphrase';

/// Reads [testPassphrase], as the keystore would.
Future<String?> readTestPassphrase() async => testPassphrase;

/// Where this app's encrypted data lives.
final E2eLayout inventoryLayout = E2eLayout.of('inventory-sync/devices');

/// Keystore contents of a device that has the passphrase.
const Map<String, String> e2eSecureSeed = {
  'crdt_sync_e2e_passphrase': testPassphrase,
};

/// Cheap Argon2id, a fresh copy memo and an unlocked indicator per test.
void resetE2eForTest() {
  e2eArgon2Params = testArgon2;
  e2eLocked.value = false;
  resetE2eCopyMemo();
}
