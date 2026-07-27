// coverage:ignore-file
// Entry point for the desktop wrapper: resolves real paths, starts the server,
// and launches the browser. The serving logic it delegates to is covered by
// test/desktop/wrapper_server_test.dart.
import 'dart:io';

import 'package:home_inventory/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

/// Port must stay fixed: the browser keys IndexedDB (the whole inventory) by
/// origin, so a different port looks like a fresh install with nothing in it.
/// Kept in step with lib/sync/desktop_wrapper.dart.
const _port = 8733;

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('HOME is not set; cannot resolve the backup path.');
    exit(1);
  }

  // `dart build cli` emits bundle/bin/<exe> alongside bundle/lib/, so the
  // installed layout is /opt/home-inventory/bin/home-inventory-desktop with
  // the web assets one level up. --web-root overrides for a run straight out
  // of the repo.
  final webRoot =
      _argValue(args, '--web-root') ??
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '..', 'web'));
  if (!Directory(webRoot).existsSync()) {
    stderr.writeln('web assets not found at $webRoot');
    exit(1);
  }

  // Overridable so a verification run cannot point at the real backup: an app
  // that starts with an empty store would overwrite it.
  final server = WrapperServer(
    webRoot: webRoot,
    logPath:
        _argValue(args, '--log-path') ??
        p.join(
          home,
          '.local',
          'share',
          'home-inventory-desktop',
          'home_inventory.json',
        ),
  );
  await server.start(_port);
  stdout.writeln('home_inventory desktop serving on http://localhost:$_port');

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
        'Still serving on http://localhost:$_port — Ctrl-C to stop.',
      );
      return;
    }
    // Otherwise the browser owned the session: its window closed, so we exit.
    await server.stop();
  }
}

/// Launches the app in a Chrome-family browser with a **stable** profile
/// directory, since the inventory lives in that profile's IndexedDB.
///
/// Returns true when the browser ran long enough to have owned the session.
Future<bool> _launchBrowser(String home) async {
  // Deliberately broad: this machine runs Thorium behind /opt/google/chrome
  // and has a policy that uninstalls the `chromium` package, so assuming any
  // single browser is wrong. INVENTORY_BROWSER overrides.
  final candidates = [
    Platform.environment['INVENTORY_BROWSER'] ?? '',
    '/opt/google/chrome/chrome',
    '/opt/thorium-browser/thorium-browser',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/brave',
  ];
  final browser = candidates.firstWhere(
    (path) => path.isNotEmpty && File(path).existsSync(),
    orElse: () => '',
  );
  if (browser.isEmpty) {
    stderr.writeln(
      'No Chrome-family browser found; open http://localhost:$_port manually.',
    );
    return false;
  }
  // The profile directory must stay stable: the inventory (IndexedDB) lives
  // inside it, so a changing path silently hides everything the user owns.
  final profile = p.join(
    home,
    '.local',
    'share',
    'home-inventory-desktop',
    'profile',
  );
  final process = await Process.start(browser, [
    '--app=http://localhost:$_port',
    '--user-data-dir=$profile',
    // Sets WM_CLASS, which the .desktop entry matches via StartupWMClass.
    // Without it the window inherits the browser's class and the taskbar shows
    // a browser icon instead of this app's.
    '--class=home-inventory',
    '--no-first-run',
  ]);

  final started = DateTime.now();
  await process.exitCode;
  return DateTime.now().difference(started) > const Duration(seconds: 5);
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
