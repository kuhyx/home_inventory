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

  /// The last status line, empty when there is nothing to say.
  final String status;

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
    final device = pending;
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(
          Icons.cloud_sync_outlined,
          semanticLabel: 'Advanced sync (GitHub)',
        ),
      ),
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
            Text(
              'A GitHub token is stored.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (device != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              'Enter code ${device.userCode} at '
              '${device.verificationUri}',
              style: theme.textTheme.titleMedium,
            ),
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
            Text(status),
          ],
          const Divider(),
          Text(
            'This device: $nodeId',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
