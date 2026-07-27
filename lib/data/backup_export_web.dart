/// Saving a backup from the browser — including the Chrome-wrapper desktop app.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Suggested file name for a manual backup, shared by every platform so the
/// user recognises the file when importing it back.
const backupFileName = 'home-inventory-backup.json';

/// The type group both the save and the open dialog restrict to.
const backupTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  uniformTypeIdentifiers: ['public.json'],
  mimeTypes: ['application/json'],
);

/// Hands [json] to the browser's download manager.
///
/// There is no save dialog to cancel here: `XFile.saveTo` on web clicks a
/// synthetic anchor, so the path argument is ignored and the browser's own
/// download UI decides where the file lands.
Future<String> exportBackup(String json, int itemCount) async {
  final file = XFile.fromData(
    utf8.encode(json),
    mimeType: 'application/json',
    name: backupFileName,
  );
  await file.saveTo('');
  final label = itemCount == 1 ? 'item' : 'items';
  return 'Downloaded $itemCount $label as $backupFileName';
}
