/// The GitHub mirror screen's form, without any of its plumbing.
library;

import 'package:flutter/material.dart';
import 'package:github_device_auth/github_device_auth.dart';
import 'package:home_inventory/sync/sync_settings.dart';
import 'package:home_inventory/ui/theme.dart';

/// Owner/repo fields, the connect buttons, the token fallback and a status.
class GitHubMirrorForm extends StatelessWidget {
  /// Creates the form.
  const GitHubMirrorForm({
    required this.ownerController,
    required this.repoController,
    required this.tokenController,
    required this.settings,
    required this.pending,
    required this.busy,
    required this.status,
    required this.statusOk,
    required this.nodeId,
    required this.onConnect,
    required this.onTest,
    required this.onSyncNow,
    required this.onSaveToken,
    super.key,
  });

  /// Controller for the repository owner.
  final TextEditingController ownerController;

  /// Controller for the repository name.
  final TextEditingController repoController;

  /// Controller for the pasted personal token.
  final TextEditingController tokenController;

  /// Settings as last loaded, or null before the first read.
  final SyncSettings? settings;

  /// The device-flow code currently waiting to be entered, if any.
  final DeviceCodeResponse? pending;

  /// Whether an action is in flight, which disables every button.
  final bool busy;

  /// The last status line, spoken only; empty when there is nothing to say.
  final String status;

  /// Whether the last action worked: a tick, else an error glyph.
  final bool statusOk;

  /// This device's sync node id, shown at the bottom.
  final String nodeId;

  /// Starts the device flow.
  final VoidCallback onConnect;

  /// Checks the configured repo is reachable.
  final VoidCallback onTest;

  /// Runs one sync now.
  final VoidCallback onSyncNow;

  /// Stores the pasted token.
  final VoidCallback onSaveToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppStatusColors>()!;
    final device = pending;
    return Scaffold(
      // The glyph sits in the title, not `leading`, so the pushed route
      // keeps its back arrow (web and the Chrome --app window have no
      // system back).
      appBar: AppBar(
        title: const Icon(
          Icons.cloud_sync_outlined,
          semanticLabel: 'Advanced sync (GitHub)',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Textgate: the "legacy, prefer Firebase" note as a warning glyph.
          Icon(
            Icons.warning_amber,
            color: palette.warning,
            semanticLabel:
                'The cutover mirror, not recommended once every device has '
                'moved to Firebase.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: ownerController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline, semanticLabel: 'Owner'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: repoController,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.folder_outlined,
                semanticLabel: 'Repository',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (settings?.isConfigured ?? false)
            Icon(
              Icons.key,
              color: palette.success,
              semanticLabel: 'A GitHub token is stored.',
            ),
          if (device != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // GitHub's own code and URL (platform content), behind glyphs.
            _glyphRow(
              Icons.pin_outlined,
              SelectableText(
                device.userCode,
                style: theme.textTheme.titleMedium,
              ),
            ),
            _glyphRow(Icons.link, SelectableText(device.verificationUri)),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('connect_github'),
            onPressed: busy ? null : onConnect,
            child: const Icon(
              Icons.cloud_upload_outlined,
              semanticLabel: 'Connect GitHub',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('test_github_connection'),
            onPressed: busy ? null : onTest,
            child: const Icon(
              Icons.check_circle_outline,
              semanticLabel: 'Test GitHub connection',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('sync_now'),
            onPressed: busy ? null : onSyncNow,
            child: const Icon(Icons.sync_outlined, semanticLabel: 'Sync now'),
          ),
          const Divider(),
          TextField(
            controller: tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.key_outlined,
                semanticLabel: 'Personal token',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('save_token'),
            onPressed: busy ? null : onSaveToken,
            child: const Icon(Icons.save_outlined, semanticLabel: 'Save token'),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Icon(
              statusOk ? Icons.check_circle : Icons.error,
              key: const Key('mirror_status'),
              color: statusOk ? palette.success : theme.colorScheme.error,
              semanticLabel: status,
            ),
          ],
          const Divider(),
          _glyphRow(
            Icons.smartphone,
            Text(
              nodeId,
              semanticsLabel: 'This device: $nodeId',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A glyph naming a value, then the value itself.
  static Widget _glyphRow(IconData icon, Widget value) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: AppSpacing.sm),
      Flexible(child: value),
    ],
  );
}
