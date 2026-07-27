import 'package:crdt_sync/crdt_sync.dart';
import 'package:idb_shim/idb.dart';

/// [LogPersistence] backed by IndexedDB, for the Chrome-wrapper desktop build.
///
/// IndexedDB rather than `localStorage`: the latter caps at roughly 5-10MB per
/// origin and is evicted more eagerly, and the inventory log is the primary
/// copy of the data, not a cache.
class WebLogPersistence implements LogPersistence {
  /// Creates a persistence over an already-opened [database].
  WebLogPersistence({required Database database}) : _db = database;

  final Database _db;

  /// Object store holding a single record: the serialised log.
  static const storeName = 'log';

  /// Key of that single record.
  static const recordKey = 'inventory';

  /// IndexedDB database name.
  static const databaseName = 'home_inventory';

  /// Opens (creating if needed) the IndexedDB database backing the log.
  static Future<Database> openDatabase(IdbFactory factory) => factory.open(
    databaseName,
    version: 1,
    onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName);
      }
    },
  );

  @override
  Future<String?> read() async {
    final txn = _db.transaction(storeName, idbModeReadOnly);
    final value = await txn.objectStore(storeName).getObject(recordKey);
    await txn.completed;
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  @override
  Future<void> write(String text) async {
    final txn = _db.transaction(storeName, idbModeReadWrite);
    await txn.objectStore(storeName).put(text, recordKey);
    await txn.completed;
  }
}
