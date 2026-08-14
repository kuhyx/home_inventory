import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/github_mirror_screen.dart';
import 'package:home_inventory/screens/settings_screen.dart';
import 'package:sync_settings_ui/sync_settings_ui.dart';

import '../support/builders.dart';
import '../support/file_selector_fake.dart';
import '../support/pump.dart';

void main() {
  late ItemRepository repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    repo = await ItemRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async {
    await repo.close();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      SettingsScreen(
        repository: repo,
        // Injected so the widget never reaches for the platform: the real
        // factories want an application-support directory and the OS
        // keystore, neither of which exists under `flutter test`.
        firebaseFactory: () async => null,
        accountLoader: () async => null,
        sessionProbe: () async => false,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the two sync links and no inline sync fields', (
    tester,
  ) async {
    await pumpSettings(tester);

    // The slim screen only links out; neither sync surface's own widgets
    // should be inlined here anymore.
    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Advanced sync (GitHub)'), findsOneWidget);
    expect(find.text('Connect GitHub'), findsNothing);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('Tapping "Sync settings" navigates to SyncSettingsScreen', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Sync settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsScreen), findsOneWidget);
  });

  testWidgets(
    'Tapping "Advanced sync (GitHub)" navigates to GitHubMirrorScreen with '
    'the right repository',
    (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Advanced sync (GitHub)'));
      await tester.pumpAndSettle();

      expect(find.byType(GitHubMirrorScreen), findsOneWidget);
      // Prove the hand-off actually carries the repository, not just that
      // the right widget type appears — a dropped constructor arg is the
      // failure mode a screen split like this one actually produces.
      final screen = tester.widget<GitHubMirrorScreen>(
        find.byType(GitHubMirrorScreen),
      );
      expect(screen.repository, repo);
    },
  );

  group('BackupSlot wiring through Sync settings', () {
    // These prove the closures SettingsScreen builds for
    // SyncSettingsScreen's BackupSlot actually call home_inventory's real
    // export/import — the shared package's own suite covers the generic
    // BackupSlot UI (button taps, status text), so these focus on the real
    // behavior behind the closures instead of re-asserting status text.

    late FakeFileSelector selector;
    late Directory temp;

    setUp(() async {
      selector = FakeFileSelector();
      FileSelectorPlatform.instance = selector;
      temp = await Directory.systemTemp.createTemp('home_inventory_settings');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    /// Taps [label] and lets the real filesystem work finish.
    ///
    /// `flutter_test` runs inside a fake-async zone where `dart:io` futures
    /// never complete, so a plain `pumpAndSettle` here asserts against a file
    /// that has been created but not yet written. `runAsync` turns the real
    /// event loop; the pump afterwards is what renders the status line.
    Future<void> tapAndFlush(WidgetTester tester, String label) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('Export inventory writes the whole log to a chosen file', (
      tester,
    ) async {
      await repo.upsert(itemFixture(id: 'a', name: 'Cable'));
      final path = '${temp.path}/backup.json';
      selector.saveLocation = FileSaveLocation(path);
      await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();
      await tapAndFlush(tester, 'Export inventory');

      expect(File(path).readAsStringSync(), contains('Cable'));
      expect(find.text('Exported inventory.'), findsOneWidget);
    });

    testWidgets(
      'a cancelled export reports success — BackupSlot has no cancelled '
      'outcome',
      (tester) async {
        selector.saveLocation = null;
        await pumpSettings(tester);

        await tester.tap(find.text('Sync settings'));
        await tester.pumpAndSettle();
        await tapAndFlush(tester, 'Export inventory');

        // exportBackup() returns normally on a cancelled picker (it just
        // never wrote anything), and BackupSlot.export has no "cancelled"
        // signal to distinguish that from a real export — this matches
        // every other app's BackupSlot wiring.
        expect(find.text('Exported inventory.'), findsOneWidget);
      },
    );

    testWidgets('Import inventory reads the picked file and merges', (
      tester,
    ) async {
      final source = await ItemRepository.openInMemory(nodeId: 'other');
      addTearDown(source.close);
      await source.upsert(itemFixture(id: 'a', name: 'Cable'));
      final path = '${temp.path}/backup.json';
      File(path).writeAsStringSync(source.exportJson());
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();
      await tapAndFlush(tester, 'Import inventory');

      expect(repo.item('a')!.name, 'Cable');
      expect(find.text('Imported inventory.'), findsOneWidget);
    });

    testWidgets(
      'a cancelled import reports success — nothing was merged',
      (tester) async {
        selector.fileToOpen = null;
        await pumpSettings(tester);

        await tester.tap(find.text('Sync settings'));
        await tester.pumpAndSettle();
        await tapAndFlush(tester, 'Import inventory');

        // Same BackupSlot limitation as export: a cancelled picker returns
        // normally, so the screen reports "Imported inventory." either way.
        // What actually matters — that nothing was merged — is asserted
        // directly.
        expect(repo.listItems(), isEmpty);
      },
    );

    // Picking the wrong file is ordinary user input. The decoder throws a
    // TypeError (an Error, not an Exception) on JSON of the wrong shape,
    // which _import rethrows as an Exception so SyncSettingsScreen's
    // "Import failed: …" status line covers it instead of an unhandled
    // error in a button callback.
    testWidgets('the wrong file is reported, not thrown', (tester) async {
      final path = '${temp.path}/wrong.json';
      File(path).writeAsStringSync('[1, 2, 3]');
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();
      await tapAndFlush(tester, 'Import inventory');

      expect(
        find.textContaining('not an inventory backup'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file that is not JSON at all is reported too', (
      tester,
    ) async {
      final path = '${temp.path}/notes.txt';
      File(path).writeAsStringSync('shopping list');
      selector.fileToOpen = XFile(path);
      await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();
      await tapAndFlush(tester, 'Import inventory');

      expect(
        find.textContaining('not an inventory backup'),
        findsOneWidget,
      );
    });
  });
}
