import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/main.dart';
import 'package:home_inventory/screens/home_shell.dart';
import 'package:home_inventory/sync/auto_sync.dart';
import 'package:home_inventory/ui/theme.dart';

void main() {
  late ItemRepository repo;

  setUp(() async {
    repo = await ItemRepository.openInMemory();
  });

  tearDown(() async {
    await repo.close();
  });

  testWidgets('opens on the home surface with the repository wired in', (
    tester,
  ) async {
    await tester.pumpWidget(HomeInventoryApp(repository: repo));
    await tester.pump();

    final shell = tester.widget<HomeShell>(find.byType(HomeShell));
    expect(shell.repository, same(repo));
  });

  // Both themes, not just the active one: a dark-mode phone and the desktop
  // Chrome window pick different ones from the same widget, and a missing
  // `AppStatusColors` extension only shows up on whichever was left unwired.
  testWidgets('carries both shared themes', (tester) async {
    await tester.pumpWidget(HomeInventoryApp(repository: repo));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Inventory');
    expect(app.theme?.extension<AppStatusColors>(), isNotNull);
    expect(app.darkTheme?.extension<AppStatusColors>(), isNotNull);
    expect(app.theme?.brightness, Brightness.light);
    expect(app.darkTheme?.brightness, Brightness.dark);
  });

  // Offline-first: sync starts by itself on launch and when the app comes
  // back to the foreground, never only from the "Sync now" button.
  testWidgets('syncs on launch and on resume without a tap', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      HomeInventoryApp(
        repository: repo,
        sync: () async {
          calls++;
          return AutoSyncResult.synced;
        },
      ),
    );
    await tester.pump();
    expect(calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(calls, 2, reason: 'leaving the app pushes at once');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 3, reason: 'coming back pulls');

    // Unmount so the shell's timers are cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
