/// The browser half of the desktop app's on-disk backup.
library;

import 'package:home_inventory/sync/desktop_wrapper.dart';
import 'package:http/http.dart' as http;

/// Mirrors the inventory log to the desktop wrapper's on-disk copy.
///
/// Deliberately fire-and-forget and entirely optional: the wrapper is an
/// optimisation, and the app must stay fully usable without it — for instance
/// when the same web build is opened in a plain browser tab, where nothing is
/// listening on the wrapper's port.
///
/// It exists because moving the desktop app into a browser would otherwise
/// make a wiped Chrome profile a total-loss event for anything not yet synced
/// to GitHub.
class DesktopBackupClient {
  /// Creates a client talking to the wrapper at [origin].
  DesktopBackupClient({http.Client? httpClient, String? origin})
    : _http = httpClient ?? http.Client(),
      _origin = origin ?? desktopWrapperOrigin;

  final http.Client _http;
  final String _origin;

  Uri get _logUri => Uri.parse('$_origin/backup/log');

  /// Reads the on-disk copy, or null when there is none or no wrapper.
  Future<String?> readLog() async {
    try {
      final response = await _http.get(_logUri);
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      return response.body;
    } on Exception {
      // No wrapper listening — a plain browser tab, or the desktop app not
      // running. Not an error; the caller falls back to IndexedDB.
      return null;
    }
  }

  /// Writes [text] to the on-disk copy. Failures are swallowed.
  Future<void> writeLog(String text) async {
    try {
      await _http.post(_logUri, body: text);
    } on Exception {
      // Same reasoning as readLog: the mirror is best-effort by design.
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _http.close();
}
