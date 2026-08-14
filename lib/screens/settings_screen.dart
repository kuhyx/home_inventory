/// Where the user connects a sync backend and triggers a sync.
///
/// Firebase is the primary path: sign in with the shared sync account, whose
/// password is kept in the OS keystore. GitHub is only the cutover mirror, so
/// its owner/repo and device-flow connection sit under "Advanced (GitHub
/// mirror)" rather than competing with Firebase as a visible choice.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:home_inventory/data/backup_export.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/firebase_backend.dart';
import 'package:home_inventory/sync/github_device_auth.dart';
import 'package:home_inventory/sync/google_sign_in_backend.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:home_inventory/sync/sync_state_factory.dart';
import 'package:home_inventory/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Sync backend connection and manual sync.
class SettingsScreen extends StatefulWidget {
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

  /// Injectable clock.
  final DateTime Function()? now;

  /// Builds the Firebase backend. Injected so tests can supply a fake, or
  /// null to assert the pre-migration GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Keystore accessors for the Firebase account. Injected as a group so the
  /// connect/disconnect flows are testable without a platform channel --
  /// `flutter test` has no binding for one.
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
  /// "not connected".
  final Future<bool> Function()? sessionProbe;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _token = TextEditingController();

  final _email = TextEditingController();
  final _password = TextEditingController();

  SyncSettings? _settings;
  String _status = '';
  bool _busy = false;
  bool _firebaseConnected = false;
  DeviceCodeResponse? _pending;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the screen renders with empty fields and fills in when
    // storage answers, so there is nothing to await here.
    unawaited(_load());
    unawaited(_loadFirebaseAccount());
  }

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _token.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Reflects a previously-stored account, so a returning user sees the real
  /// state instead of an empty form that looks unconfigured.
  Future<void> _loadFirebaseAccount() async {
    final account = await (widget.accountLoader ?? loadAccount)();
    // The stored session, not the account marker, decides "connected": a
    // Google sign-in leaves a refresh token that authenticates every request
    // even when no marker was written beside it.
    final connected = await (widget.sessionProbe ?? isFirebaseConfigured)();
    if (!mounted) return;
    if (account != null) _email.text = account.email;
    setState(() => _firebaseConnected = connected);
  }

  /// Stores the typed account and signs in immediately, so a typo surfaces
  /// here rather than as a silent background failure on the next sync.
  ///
  /// Without this the app could never reach Firebase at all: `openFirebase()`
  /// would read an account nothing had ever written.

  /// Signs in by picking a Google account -- the one-tap path.
  ///
  /// A dismissed picker is not an error; a wrong-account sign-in reports why,
  /// because that is the failure that otherwise looks like a working sync
  /// which silently never syncs.
  Future<void> _connectGoogle() async {
    setState(() {
      _busy = true;
      _status = 'Signing in...';
    });
    try {
      final client =
          await (widget.googleFirebaseFactory ?? openFirebaseWithGoogle)();
      if (!mounted) return;
      if (client == null) {
        setState(() {
          _busy = false;
          _status = 'Google sign-in was cancelled.';
        });
        return;
      }
      // openFirebaseWithGoogle stored the account under the email Firebase
      // reported; reflect it rather than reading the (empty) form field.
      final account = await (widget.accountLoader ?? storedAccount)();
      // Report the persisted state, not the fact that the call returned a
      // client: a non-null client only means sign-in succeeded in that
      // moment, which is how four apps claimed "Connected" and then synced
      // over GitHub after the next restart.
      final connected = await (widget.sessionProbe ?? isFirebaseConfigured)();
      if (!mounted) return;
      if (account != null) _email.text = account.email;
      setState(() {
        _busy = false;
        _firebaseConnected = connected;
        _status = connected
            ? 'Connected to Firebase.'
            : 'Signed in, but this device did not save the session - it will '
                  'sync over GitHub after a restart. Try connecting again.';
      });
    } on FirebaseAuthError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = error.message;
      });
    } on Object catch (error) {
      // Broader than Exception on purpose: a missing platform binding raises
      // an Error, and anything escaping here leaves the button disabled and
      // the screen stuck on "Signing in..." forever -- which is exactly what
      // happened on the phone before storedAccount() replaced loadAccount().
      if (!mounted) return;
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = 'Google sign-in failed: $error';
      });
    }
  }

  Future<void> _connectFirebase() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _status = 'Enter the sync account email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Signing in...';
    });
    await (widget.accountSaver ?? saveAccount)(
      FirebaseAccount(email: email, password: password),
    );
    final client = await (widget.firebaseFactory ?? openFirebase)();
    if (!mounted) return;
    if (client == null) {
      await (widget.accountClearer ?? clearAccount)();
      setState(() {
        _busy = false;
        _firebaseConnected = false;
        _status = 'Firebase rejected that account.';
      });
      return;
    }
    _password.clear();
    setState(() {
      _busy = false;
      _firebaseConnected = true;
      _status = 'Connected to Firebase.';
    });
  }

  Future<void> _disconnectFirebase() async {
    await (widget.accountClearer ?? clearAccount)();
    if (!mounted) return;
    _email.clear();
    _password.clear();
    setState(() {
      _firebaseConnected = false;
      _status = 'Firebase disconnected.';
    });
  }

  Future<void> _load() async {
    final settings = await SyncSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _owner.text = settings.owner;
      _repo.text = settings.repo;
    });
  }

  SyncSettings _current() {
    final base =
        _settings ?? const SyncSettings(owner: '', repo: '', token: '');
    return base.copyWith(
      owner: _owner.text.trim(),
      repo: _repo.text.trim(),
    );
  }

  Future<void> _persist(SyncSettings settings) async {
    await settings.save();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  /// Runs [action], keeping the screen busy and reporting whatever it says.
  ///
  /// Every network path funnels through here so a failure always becomes a
  /// status line rather than an unhandled exception — sync is optional, and
  /// losing it must never take the app down with it.
  Future<void> _guard(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    String message;
    try {
      message = await action();
    } on DeviceAuthException catch (error) {
      // Only this one is special-cased: its `message` is the human-readable
      // half, and toString() would prefix it with the exception's own name.
      // Everything else — including GitHubSyncError, which the client already
      // wraps transport failures into — renders identically either way, so a
      // single catch-all handles them.
      message = error.message;
    } on Exception catch (error) {
      message = '$error';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }

  Future<void> _saveToken() async {
    final token = _token.text.trim();
    if (token.isEmpty) return;
    await _guard(() async {
      await _persist(_current().copyWith(token: token));
      _token.clear();
      return 'Token saved.';
    });
  }

  Future<void> _testConnection() => _guard(() async {
    final settings = _current();
    await _persist(settings);
    final client = GitHubClient(
      owner: settings.owner,
      repo: settings.repo,
      token: settings.token,
      httpClient: widget.httpClient,
    );
    try {
      final ok = await client.canAccessRepo();
      return ok
          ? 'Connected to ${settings.owner}/${settings.repo}.'
          : 'Cannot reach ${settings.owner}/${settings.repo}.';
    } finally {
      client.close();
    }
  });

  Future<void> _syncNow() => _guard(() async {
    final settings = _current();
    // Either backend counts: a device connected only to Firebase is fully
    // configured, and gating on the GitHub token alone would lock it out of
    // syncing entirely once the mirror is retired.
    if (!settings.isConfigured && !_firebaseConnected) {
      return 'Connect a sync backend in Settings first.';
    }
    await _persist(settings);

    // Firebase is the primary backend when this device has been set up for
    // it; GitHub stays as a mirror until every device has moved. Not being
    // set up is a normal state, not an error -- the app keeps syncing over
    // GitHub exactly as before.
    // `openFirebase` is the production default; tests always inject, because
    // the real one reaches the OS keystore through a platform channel.
    final factory = widget.firebaseFactory ?? openFirebase;
    final firebase = await factory();
    try {
      final outcome = await SyncService(widget.repository).sync(
        owner: settings.owner,
        repo: settings.repo,
        token: settings.token,
        firebase: firebase,
        stateStore: widget.stateStore ?? await openSyncStateStore(),
        httpClient: widget.httpClient,
        now: widget.now?.call(),
      );
      final n = outcome.itemCount;
      final via = firebase == null ? 'GitHub' : 'Firebase';
      return 'Synced via $via — $n ${n == 1 ? 'item' : 'items'}.';
    } finally {
      firebase?.close();
    }
  });

  Future<void> _export() => _guard(
    () => exportBackup(
      widget.repository.exportJson(),
      widget.repository.listItems().length,
    ),
  );

  Future<void> _import() => _guard(() async {
    final file = await openFile(
      acceptedTypeGroups: const [backupTypeGroup],
    );
    if (file == null) return 'Import cancelled.';
    final text = await file.readAsString();
    try {
      await widget.repository.importJson(text);
    } on Object catch (error) {
      // Deliberately broader than Exception: a file that is valid JSON but the
      // wrong shape surfaces as a TypeError from the log decoder, and a user
      // picking the wrong file is ordinary input, not a bug to crash on.
      return 'That file is not an inventory backup ($error).';
    }
    final n = widget.repository.listItems().length;
    return 'Imported — $n ${n == 1 ? 'item' : 'items'} now.';
  });

  Future<void> _connect() => _guard(() async {
    final settings = _current();
    if (!settings.canUseDeviceFlow) return 'No client id configured.';
    final auth = GitHubDeviceAuth(
      clientId: settings.clientId,
      httpClient: widget.httpClient,
    );
    try {
      final device = await auth.requestDeviceCode();
      if (!mounted) return 'Cancelled.';
      setState(() => _pending = device);
      // Genuinely best-effort, hence the swallow: the user code is already on
      // screen, so on a machine with no browser they can still type the URL
      // by hand. Letting the launch failure propagate would abandon a device
      // flow that was about to succeed.
      try {
        await launchUrl(
          Uri.parse(device.verificationUri),
          mode: LaunchMode.externalApplication,
        );
      } on Exception {
        // Ignored on purpose — see above.
      }
      final token = await auth.pollForToken(device);
      await _persist(settings.copyWith(token: token));
      if (mounted) setState(() => _pending = null);
      return 'Connected to GitHub.';
    } finally {
      auth.close();
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Firebase sync', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _firebaseConnected
                ? 'Connected. Syncs go to Firebase first, and still mirror '
                      'to GitHub until every device has moved.'
                : 'Not connected - syncing over GitHub only. Enter the '
                      'shared sync account to move this device over. The '
                      'password is kept in the device keystore, never in the '
                      'app or the repo.',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Once connected the account is read-only text: an editable email
          // box beside an empty password box reads as "you still have to
          // enter this", making a connected device look unconfigured.
          if (_firebaseConnected)
            Row(
              children: [
                const Icon(Icons.cloud_done, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_email.text)),
                TextButton(
                  onPressed: _busy ? null : _disconnectFirebase,
                  child: const Text('Disconnect'),
                ),
              ],
            )
          else ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Sync account email',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Sync account password',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _busy ? null : _connectFirebase,
              icon: const Icon(Icons.cloud_done),
              label: const Text('Connect Firebase'),
            ),
            // One tap, no typing -- the path that matters after a
            // reinstall. Hidden where the platform has no programmatic
            // Google flow (see google_platform.dart); a button that
            // always failed would be worse than none.
            if (widget.googleAvailable ?? googleSignInSupported) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _connectGoogle,
                icon: const Icon(Icons.account_circle),
                label: const Text('Sign in with Google'),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          // GitHub is the cutover mirror, not a choice competing with
          // Firebase, so its whole setup lives behind one disclosure.
          ExpansionTile(
            title: const Text('Advanced (GitHub mirror)'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              TextField(
                controller: _owner,
                decoration: const InputDecoration(labelText: 'Owner'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _repo,
                decoration: const InputDecoration(labelText: 'Repository'),
              ),
              const SizedBox(height: AppSpacing.md),
              if (settings != null && settings.isConfigured)
                Text(
                  'A GitHub token is stored.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (pending != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  'Enter code ${pending.userCode} at '
                  '${pending.verificationUri}',
                  style: theme.textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: const Text('Connect GitHub'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _busy ? null : _testConnection,
                child: const Text('Test GitHub connection'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _syncNow,
            child: const Text('Sync now'),
          ),
          const Divider(),
          // The fallback for anything the device flow cannot do — a fine
          // grained PAT, or a machine with no browser at all.
          Text('Or paste a token', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Personal token'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _saveToken,
            child: const Text('Save token'),
          ),
          const Divider(),
          // The offline half of the same job: sync needs GitHub and a network,
          // a backup file needs neither, and the two failure modes (account
          // gone / device gone) are independent.
          Text('Backup file', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _export,
            child: const Text('Export inventory'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _import,
            child: const Text('Import inventory'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Worth saying plainly: users expect "import" to mean "restore
            // over the top", and a merge behaves differently when the file is
            // older than what is on the device.
            'Importing merges — nothing already here is lost.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_status),
          ],
          const Divider(),
          Text(
            'This device: ${widget.repository.nodeId}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
