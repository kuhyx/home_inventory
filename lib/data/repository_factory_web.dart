import 'package:home_inventory/data/desktop_backup_client.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/web_log_persistence.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Opens the inventory store in a browser (the Chrome-wrapper desktop build).
///
/// Never imported by a test: doing so would compile `dart:js_interop` and
/// `idb_browser` into the VM test binary, which both fails to run and adds a
/// permanently 0%-covered file to the coverage gate. Under the VM the
/// conditional export in `repository_factory.dart` resolves to the io variant,
/// so this file simply never appears in `lcov.info`.
Future<ItemRepository> openRepository() async {
  final database = await WebLogPersistence.openDatabase(idbFactoryBrowser);
  final persistence = WebLogPersistence(
    database: database,
    backup: DesktopBackupClient(),
  );

  final prefs = await SharedPreferences.getInstance();
  var nodeId = prefs.getString(ItemRepository.kNodeId) ?? '';
  if (nodeId.isEmpty) {
    nodeId = const Uuid().v4();
    await prefs.setString(ItemRepository.kNodeId, nodeId);
  }
  return ItemRepository.openWith(persistence: persistence, nodeId: nodeId);
}
