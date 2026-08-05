import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/main.dart';
import 'package:home_inventory/screens/home_shell.dart';
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
}
