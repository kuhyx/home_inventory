/// Saving a backup on a host that has `dart:io`: Android, and Linux desktop.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Suggested file name for a manual backup, shared by every platform so the
/// user recognises the file when importing it back.
const backupFileName = 'home-inventory-backup.json';

/// The type group both the save and the open dialog restrict to.
const backupTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  // Needed by the macOS/iOS pickers and harmless elsewhere; a group with no
  // recognised identifier silently matches nothing on those hosts.
  uniformTypeIdentifiers: ['public.json'],
  mimeTypes: ['application/json'],
);

/// Writes [json] somewhere the user can get at it, and returns a line
/// describing where it went.
///
/// On mobile this opens the system share sheet, because Android's file_selector
/// implements only the open side — asking for a save dialog there throws
/// [UnimplementedError] rather than falling back to anything.
Future<String> exportBackup(String json, int itemCount) async {
  // '1 items' has been shipped and caught once already (commit 6d0df13, the
  // summary strip). Every user-facing count in this app goes through a plural
  // check.
  final label = itemCount == 1 ? 'item' : 'items';
  // coverage:ignore-start
  // Mobile-only share path: Platform.isAndroid/isIOS are always false on the
  // Linux test host, so these lines are structurally unreachable under
  // `flutter test` and excluded from the coverage denominator rather than
  // faked into a false green. Verified on-device.
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$backupFileName');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Home inventory backup ($itemCount $label)',
      ),
    );
    return 'Shared a backup of $itemCount $label.';
  }
  // coverage:ignore-end
  final location = await getSaveLocation(
    suggestedName: backupFileName,
    acceptedTypeGroups: const [backupTypeGroup],
  );
  if (location == null) return 'Export cancelled.';
  await File(location.path).writeAsString(json);
  return 'Exported $itemCount $label to ${location.path}';
}
