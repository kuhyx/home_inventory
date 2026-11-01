import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/backup_export.dart';

import '../support/file_selector_fake.dart';

void main() {
  late FakeFileSelector selector;
  late Directory temp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    selector = FakeFileSelector();
    FileSelectorPlatform.instance = selector;
    temp = await Directory.systemTemp.createTemp('home_inventory_export');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('writes the payload to the chosen path', () async {
    final path = '${temp.path}/backup.json';
    selector.saveLocation = FileSaveLocation(path);

    final message = await exportBackup('{"a":1}', 3);

    expect(File(path).readAsStringSync(), '{"a":1}');
    expect(message, 'Exported 3 items.');
  });

  // '1 items' shipped once already (commit 6d0df13, the summary strip), so
  // every user-facing count in this app gets a plural check.
  test('counts one item in the singular', () async {
    final path = '${temp.path}/backup.json';
    selector.saveLocation = FileSaveLocation(path);

    final message = await exportBackup('{}', 1);

    expect(message, 'Exported 1 item.');
  });

  test('suggests a recognisable file name', () async {
    selector.saveLocation = FileSaveLocation('${temp.path}/backup.json');

    await exportBackup('{}', 0);

    expect(selector.saveRequests, [backupFileName]);
  });

  // A cancelled dialog is an ordinary outcome, not a failure: it has to report
  // itself rather than leaving the last status line standing.
  test('reports a cancelled save without writing anything', () async {
    selector.saveLocation = null;

    final message = await exportBackup('{}', 3);

    expect(message, 'Export cancelled.');
    expect(temp.listSync(), isEmpty);
  });
}
