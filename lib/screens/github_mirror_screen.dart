/// The GitHub mirror screen: cutover-only sync transport, not a peer of
/// Firebase.
///
/// Kept app-local rather than folded into the shared `sync_settings_ui`
/// package because connecting here also triggers a real inventory sync via
/// [SyncService] -- unlike the shared package's Firebase/Backup sections,
/// which only save settings. See `lib/screens/settings_screen.dart` for the
/// dispatcher and the link to this screen and to the shared Sync settings
/// screen.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:github_device_auth/github_device_auth.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/firebase_backend.dart';
import 'package:home_inventory/sync/sync_service.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:home_inventory/sync/sync_state_factory.dart';
import 'package:home_inventory/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// GitHub mirror connection, token management, and manual sync.
class GitHubMirrorScreen extends StatefulWidget {
  /// Creates a [GitHubMirrorScreen].
  const GitHubMirrorScreen({
    required this.repository,
    this.httpClient,
    this.now,
    this.firebaseFactory,
    this.stateStore,
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
  /// null to assert the GitHub-only path still works.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Revision cache. Injected so tests need no application-support directory.
  final SyncStateStore? stateStore;

  /// Whether a Firebase session is stored.
  ///
  /// Either backend counts as "configured" for [_syncNow]'s guard: a device
  /// connected only to Firebase must not be locked out of syncing just
  /// because it never set up the GitHub mirror. Injected so tests need no
  /// keystore; production reads the real session.
  final Future<bool> Function()? sessionProbe;

  @override
  State<GitHubMirrorScreen> createState() => _GitHubMirrorScreenState();
}

class _GitHubMirrorScreenState extends State<GitHubMirrorScreen> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _token = TextEditingController();

  SyncSettings? _settings;
  String _status = '';
  bool _busy = false;
  DeviceCodeResponse? _pending;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the screen renders with empty fields and fills in when
    // storage answers, so there is nothing to await here.
    unawaited(_load());
  }

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _token.dispose();
    super.dispose();
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
    final firebaseConnected =
        await (widget.sessionProbe ?? isFirebaseConfigured)();
    if (!settings.isConfigured && !firebaseConnected) {
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
      appBar: AppBar(title: const Text('Advanced sync (GitHub)')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'The cutover mirror — not recommended once every device has '
            'moved to Firebase.',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
