/// The decisions the desktop wrapper makes before it starts anything.
///
/// Split out of `bin/home_inventory_desktop.dart` so they can be tested: what
/// is left in `bin/` is process spawning, stdout and exit codes, none of which
/// a test can meaningfully assert. Everything here is pure — the filesystem
/// arrives as an `exists` callback rather than a `dart:io` import — which also
/// keeps the file safe to compile anywhere.
library;

import 'package:home_inventory/sync/desktop_wrapper.dart';
import 'package:path/path.dart' as p;

/// How long the browser must stay up to count as having owned the session.
///
/// Chrome exits immediately when it hands the URL to an instance that already
/// owns the profile directory, and shutting the server down then would pull it
/// out from under a window that is still open.
const browserHandoffThreshold = Duration(seconds: 5);

/// Value of `--name value` in [args], or null when absent or last.
String? argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

/// Where the packaged build keeps the web assets, given the wrapper binary.
///
/// `dart build cli` emits `bundle/bin/<exe>` alongside `bundle/lib/`, and
/// `install_arch.sh` copies that under `/opt/home-inventory`, so the installed
/// binary is `/opt/home-inventory/bin/home_inventory_desktop` with the assets
/// one level up.
String defaultWebRoot(String executablePath) =>
    p.normalize(p.join(p.dirname(executablePath), '..', 'web'));

/// Directory holding the desktop app's own state.
String desktopDataDir(String home) =>
    p.join(home, '.local', 'share', 'home-inventory-desktop');

/// The wrapper's on-disk copy of the log — the backup IndexedDB falls back to.
String desktopLogPath(String home) =>
    p.join(desktopDataDir(home), 'home_inventory.json');

/// The browser profile directory.
///
/// Must stay stable: the inventory itself lives in this profile's IndexedDB,
/// so a changing path silently hides everything the user owns.
String desktopProfileDir(String home) =>
    p.join(desktopDataDir(home), 'profile');

/// Browser executables to try, in order.
///
/// Deliberately broad: this machine runs Thorium out of `/opt` and has a
/// policy that uninstalls the `chromium` package, so assuming any single
/// browser is wrong. `INVENTORY_BROWSER` overrides.
List<String> browserCandidates(Map<String, String> environment) => [
  environment['INVENTORY_BROWSER'] ?? '',
  '/opt/google/chrome/chrome',
  '/opt/thorium-browser/thorium-browser',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/brave',
];

/// First candidate that [exists], or null when none is installed.
String? findBrowser(
  Map<String, String> environment, {
  required bool Function(String path) exists,
}) {
  for (final path in browserCandidates(environment)) {
    if (path.isNotEmpty && exists(path)) return path;
  }
  return null;
}

/// Arguments that open the app window against the wrapper.
List<String> browserArgs(String profileDir) => [
  '--app=$desktopWrapperOrigin',
  '--user-data-dir=$profileDir',
  // Sets WM_CLASS, which the .desktop entry matches via StartupWMClass.
  // Without it the window inherits the browser's class and the taskbar shows
  // a browser icon instead of this app's.
  '--class=home-inventory',
  '--no-first-run',
];
