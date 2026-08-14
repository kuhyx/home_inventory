/// Settings screen: links to the two sync surfaces.
///
/// "Sync settings" is the shared `sync_settings_ui` package (Firebase sync +
/// the inventory export/import backup, identical in shape to every other
/// kuhy app's Sync settings screen). "Advanced sync (GitHub)" stays
/// app-local ([GitHubMirrorScreen]) because connecting it also triggers a
/// real inventory sync via [SyncService], which the shared package does not
/// do.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:home_inventory/data/backup_export.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/github_mirror_screen.dart';
import 'package:home_inventory/sync/firebase_backend.dart';
import 'package:home_inventory/sync/google_sign_in_backend.dart';
import 'package:http/http.dart' as http;
import 'package:sync_settings_ui/sync_settings_ui.dart';

/// Links to the shared Sync settings screen and the app-local GitHub mirror.
class SettingsScreen extends StatelessWidget {
  /// Creates the settings screen.
  const SettingsScreen({
    required this.repository,
    this.httpClient,
    this.now,
    this.firebaseFactory,
    this.stateStore,
    this.googleFirebaseFactory,
    this.googleAvailable,
    this.accountLoader,
    this.accountSaver,
    this.accountClearer,
    this.sessionProbe,
    super.key,
  });

  /// Store to sync.
  final ItemRepository repository;

  /// Injected so tests exercise the real sync path without a network.
  final http.Client? httpClient;

  /// Injectable clock, forwarded to [GitHubMirrorScreen]'s manual sync.
  final DateTime Function()? now;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Builds the Firebase backend via Google sign-in. Separate from the
  /// password factory because it reaches the Google plugin's platform
  /// channel, which `flutter test` has no binding for.
  final Future<FirebaseRestClient?> Function()? googleFirebaseFactory;

  /// Whether to offer the Google button. Defaults to what the platform
  /// supports; injected by tests, whose host reports unsupported.
  final bool? googleAvailable;

  /// Reads the stored Firebase account. Injected so tests need no keystore.
  final Future<FirebaseAccount?> Function()? accountLoader;

  /// Persists the account. See [accountLoader].
  final Future<void> Function(FirebaseAccount)? accountSaver;

  /// Forgets the account and any cached session. See [accountLoader].
  final Future<void> Function()? accountClearer;

  /// Whether a Firebase session is stored. See [accountLoader].
  ///
  /// Separate from [accountLoader] because the two answer different
  /// questions: the account marker is bookkeeping, the session is the
  /// credential. A device can hold the second without the first, and
  /// reporting only the first is what made a syncing phone read as
  /// "not connected". Also forwarded into [GitHubMirrorScreen]'s manual-sync
  /// guard, so a Firebase-only device is never told to "connect a sync
  /// backend" first.
  final Future<bool> Function()? sessionProbe;

  /// Exports every item to a chosen file, wrapped as a [BackupSlot.export]
  /// closure. `exportBackup` returns a status string on success, which the
  /// shared screen doesn't render — its own "Exported inventory." message
  /// covers that — so only a genuine failure needs to surface here.
  Future<void> _export() async {
    await exportBackup(repository.exportJson(), repository.listItems().length);
  }

  /// Imports items from a user-picked backup file, wrapped as a
  /// [BackupSlot.import] closure.
  ///
  /// [ItemRepository.importJson] throws broader than `Exception` on purpose
  /// (a file that is valid JSON but the wrong shape surfaces as a `TypeError`
  /// from the log decoder), but [SyncSettingsScreen] only catches
  /// `Exception` for its "Import failed: …" status line. Without rethrowing
  /// as one, a wrong-shape file would escape as an unhandled error in a
  /// button callback instead of a status message.
  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [backupTypeGroup]);
    if (file == null) return; // cancelled: BackupSlot has no "cancelled"
    // outcome, so this matches every other app's import wiring.
    final text = await file.readAsString();
    try {
      await repository.importJson(text);
    } on Object catch (error) {
      throw Exception('That file is not an inventory backup ($error).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sync settings'),
            subtitle: const Text('Firebase sync and inventory backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SyncSettingsScreen(
                  accountLoader: accountLoader ?? loadAccount,
                  accountSaver: accountSaver ?? saveAccount,
                  accountClearer: accountClearer ?? clearAccount,
                  sessionProbe: sessionProbe ?? isFirebaseConfigured,
                  firebaseFactory: firebaseFactory ?? openFirebase,
                  googleFirebaseFactory:
                      googleFirebaseFactory ?? openFirebaseWithGoogle,
                  googleAvailable: googleAvailable ?? googleSignInSupported,
                  backup: BackupSlot(
                    label: 'inventory',
                    export: _export,
                    import: _import,
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced sync (GitHub)'),
            subtitle: const Text('Cutover mirror — not recommended'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => GitHubMirrorScreen(
                  repository: repository,
                  httpClient: httpClient,
                  now: now,
                  firebaseFactory: firebaseFactory,
                  stateStore: stateStore,
                  sessionProbe: sessionProbe,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
