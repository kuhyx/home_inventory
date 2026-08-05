import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/repository_factory_io.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/builders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('home_inventory_factory_');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('mints a node id on a fresh install and persists it', () async {
    SharedPreferences.setMockInitialValues({});

    final repo = await openRepositoryIn(dir.path);
    addTearDown(repo.close);

    // A uuid, not a fixed "phone"/"desktop" constant: two devices sharing a
    // node id overwrite each other's pushed file on every sync tick, so the
    // failure this guards against is silent data loss, not a crash.
    expect(repo.nodeId, hasLength(36));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ItemRepository.kNodeId), repo.nodeId);
  });

  test('reuses the stored node id instead of minting a second one', () async {
    SharedPreferences.setMockInitialValues({
      ItemRepository.kNodeId: 'node-from-a-previous-launch',
    });

    final repo = await openRepositoryIn(dir.path);
    addTearDown(repo.close);

    expect(repo.nodeId, 'node-from-a-previous-launch');
  });

  test('treats a blank stored node id as absent', () async {
    SharedPreferences.setMockInitialValues({ItemRepository.kNodeId: ''});

    final repo = await openRepositoryIn(dir.path);
    addTearDown(repo.close);

    expect(repo.nodeId, isNotEmpty);
  });

  test('writes the log under the given directory', () async {
    SharedPreferences.setMockInitialValues({});

    final repo = await openRepositoryIn(dir.path);
    addTearDown(repo.close);
    await repo.upsert(itemFixture(name: 'Kitchen roll', quantity: 2));

    final file = File(p.join(dir.path, ItemRepository.logFileName));
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('Kitchen roll'));
  });

  test('reopening the same directory sees what was written', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await openRepositoryIn(dir.path);
    await first.upsert(itemFixture(name: 'Kitchen roll', quantity: 2));
    await first.close();

    final second = await openRepositoryIn(dir.path);
    addTearDown(second.close);

    expect(second.listItems().map((item) => item.name), ['Kitchen roll']);
    // Same install, so the node id survives too — a new one per launch would
    // leave a dead peer slot in the syncs repo on every start.
    expect(second.nodeId, first.nodeId);
  });
}
