/// The explicit "Export inventory" action.
///
/// File plumbing (system Save-as on Android, a save dialog on desktop, a
/// browser download on web) lives in `data_transfer_flutter`; this file only
/// decides the file name and the status line.
library;

import 'package:data_transfer_flutter/data_transfer_flutter.dart';

/// Suggested file name for a manual backup, so the user recognises the file
/// when importing it back.
const backupFileName = 'home-inventory-backup.json';

/// Saves [json] where the user chooses, and returns a status line.
Future<String> exportBackup(String json, int itemCount) async {
  // '1 items' has been shipped and caught once already (commit 6d0df13, the
  // summary strip). Every user-facing count in this app goes through a plural
  // check.
  final label = itemCount == 1 ? 'item' : 'items';
  final saved = await exportJsonText(fileName: backupFileName, text: json);
  return saved ? 'Exported $itemCount $label.' : 'Export cancelled.';
}
