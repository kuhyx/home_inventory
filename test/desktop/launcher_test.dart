import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/desktop/launcher.dart';
import 'package:home_inventory/sync/desktop_wrapper.dart';

void main() {
  group('argValue', () {
    test('reads the value after the flag', () {
      expect(argValue(['--web-root', '/tmp/web'], '--web-root'), '/tmp/web');
    });

    test('returns null when the flag is absent', () {
      expect(argValue(['--no-browser'], '--web-root'), isNull);
    });

    // A trailing `--log-path` with nothing after it must fall back to the
    // default rather than read past the end of the list.
    test('returns null when the flag is last', () {
      expect(argValue(['--log-path'], '--log-path'), isNull);
    });

    test('ignores a bare flag of the same name elsewhere', () {
      expect(argValue(['--no-browser', '--log-path', 'a'], '--log-path'), 'a');
    });
  });

  group('paths', () {
    // Exactly the layout install_arch.sh's package() lays down: the bundle's
    // bin/ under /opt/home-inventory, with the web assets a sibling of it.
    // Only a real pacman install exercises this path — run.sh always passes
    // --web-root — so it is pinned here instead.
    test('web root sits beside the bundle bin directory', () {
      expect(
        defaultWebRoot('/opt/home-inventory/bin/home_inventory_desktop'),
        '/opt/home-inventory/web',
      );
    });

    // These three are pinned deliberately: the profile directory holds the
    // IndexedDB the whole inventory lives in, and the log path is the on-disk
    // copy a wiped profile recovers from. Moving either looks to the user like
    // the app lost everything, so a change here has to be a deliberate edit to
    // this test, not a silent refactor.
    test('data, log and profile paths are stable', () {
      expect(
        desktopDataDir('/home/kuhy'),
        '/home/kuhy/.local/share/home-inventory-desktop',
      );
      expect(
        desktopLogPath('/home/kuhy'),
        '/home/kuhy/.local/share/home-inventory-desktop/home_inventory.json',
      );
      expect(
        desktopProfileDir('/home/kuhy'),
        '/home/kuhy/.local/share/home-inventory-desktop/profile',
      );
    });
  });

  group('findBrowser', () {
    test('prefers INVENTORY_BROWSER when it exists', () {
      final found = findBrowser(
        {'INVENTORY_BROWSER': '/opt/mine/browser'},
        exists: (path) => true,
      );

      expect(found, '/opt/mine/browser');
    });

    // The override naming something that is not installed must not shadow a
    // browser that is; an empty entry is the no-override case.
    test('falls through when the override is missing or unset', () {
      expect(
        findBrowser(
          {'INVENTORY_BROWSER': '/opt/gone/browser'},
          exists: (path) => path == '/usr/bin/chromium',
        ),
        '/usr/bin/chromium',
      );
      expect(
        findBrowser({}, exists: (path) => path == '/usr/bin/chromium'),
        '/usr/bin/chromium',
      );
    });

    test('takes the first installed candidate in order', () {
      final found = findBrowser(
        {},
        exists: (path) =>
            path == '/usr/bin/brave' ||
            path == '/opt/thorium-browser/thorium-browser',
      );

      expect(found, '/opt/thorium-browser/thorium-browser');
    });

    test('returns null when nothing is installed', () {
      expect(findBrowser({}, exists: (path) => false), isNull);
    });
  });

  group('browserArgs', () {
    test('opens an app window on the wrapper origin', () {
      final args = browserArgs('/home/kuhy/profile');

      expect(args, contains('--app=$desktopWrapperOrigin'));
      expect(args, contains('--user-data-dir=/home/kuhy/profile'));
      // Sets WM_CLASS, which the .desktop entry matches via StartupWMClass;
      // without it the taskbar shows a browser icon instead of this app's.
      expect(args, contains('--class=home-inventory'));
      expect(args, contains('--no-first-run'));
    });
  });
}
