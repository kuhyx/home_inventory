// coverage:ignore-file
// Entry point for the desktop wrapper: resolves real paths, starts the server,
// and launches the browser. Every decision it makes is in
// lib/desktop/launcher.dart and covered by test/desktop/launcher_test.dart;
// the serving itself by test/desktop/wrapper_server_test.dart. What is left
// here is process spawning, stdout and exit codes.
import 'dart:io';

import 'package:home_inventory/desktop/launcher.dart';
import 'package:home_inventory/desktop/wrapper_server.dart';
import 'package:home_inventory/sync/desktop_wrapper.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('HOME is not set; cannot resolve the backup path.');
    exit(1);
  }

  // --web-root overrides for a run straight out of the repo.
  final webRoot =
      argValue(args, '--web-root') ??
      defaultWebRoot(Platform.resolvedExecutable);
  if (!Directory(webRoot).existsSync()) {
    stderr.writeln('web assets not found at $webRoot');
    exit(1);
  }

  // Overridable so a verification run cannot point at the real backup: an app
  // that starts with an empty store would overwrite it.
  final server = WrapperServer(
    webRoot: webRoot,
    logPath: argValue(args, '--log-path') ?? desktopLogPath(home),
  );
  await server.start(desktopWrapperPort);
  stdout.writeln('home_inventory desktop serving on $desktopWrapperOrigin');

  // A bare flag, not a valued option: requiring a dummy value meant passing a
  // stray positional, which the AOT runtime tries to read as a snapshot.
  if (!args.contains('--no-browser')) {
    final ranLongEnough = await _launchBrowser(home);
    if (!ranLongEnough) {
      // Chrome exits immediately when it hands the URL to an instance that
      // already owns the profile directory (or when a stale SingletonLock is
      // left behind). Shutting down here would pull the server out from under
      // a window that is still open, so keep serving instead.
      stdout.writeln(
        'Browser returned immediately (handed off to an existing window). '
        'Still serving on $desktopWrapperOrigin — Ctrl-C to stop.',
      );
      return;
    }
    // Otherwise the browser owned the session: its window closed, so we exit.
    await server.stop();
  }
}

/// Launches the app in a Chrome-family browser.
///
/// Returns true when the browser ran long enough to have owned the session.
Future<bool> _launchBrowser(String home) async {
  final browser = findBrowser(
    Platform.environment,
    exists: (path) => File(path).existsSync(),
  );
  if (browser == null) {
    stderr.writeln(
      'No Chrome-family browser found; open $desktopWrapperOrigin manually.',
    );
    return false;
  }

  final process = await Process.start(
    browser,
    browserArgs(desktopProfileDir(home)),
  );

  final started = DateTime.now();
  await process.exitCode;
  return DateTime.now().difference(started) > browserHandoffThreshold;
}
