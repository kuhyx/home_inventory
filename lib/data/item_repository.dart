/// Local-first persistence and querying for the inventory.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/derived_ids.dart';
import 'package:home_inventory/data/location_migration.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/barcode_link.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/inventory_summary.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/models/location.dart';
import 'package:home_inventory/models/location_tree.dart';
import 'package:home_inventory/models/rate_hint.dart';

part 'item_repository_barcodes.dart';
part 'item_repository_history.dart';
part 'item_repository_location_writes.dart';
part 'item_repository_locations.dart';
part 'item_repository_mapping.dart';
part 'item_repository_reads.dart';
part 'item_repository_suggestions.dart';
part 'item_repository_sync.dart';
part 'item_repository_writes.dart';

// Deliberately free of `dart:io`: the desktop app is a web build, and one
// `dart:io` import anywhere reachable from `main.dart` makes the whole app
// fail to compile for web. Choosing where the log physically lives belongs to
// `repository_factory_io.dart` / `_web.dart` behind a conditional export.

/// Local-first storage and querying for [Item]s, backed by the shared
/// `crdt_sync` [LogStore].
///
/// Every write lands in local storage first, so the app is fully usable
/// offline; sync is a separate, optional concern layered on top.
///
/// The log holds two kinds of record, told apart by [kTypeField]: mutable
/// items stored as per-field last-writer-wins values, and immutable
/// [Adjustment]s appended on every quantity change. That split exists because
/// last-writer-wins keeps only the newest value — writing `quantity` destroys
/// its own history, so the history has to live in records that are never
/// rewritten.
///
/// Filtering and sorting run in Dart over the in-memory log; a household
/// inventory is small enough that this is cheaper than any index.
class ItemRepository {
  ItemRepository._(this._store, this._nodeId);

  final LogStore _store;
  final String _nodeId;

  /// SharedPreferences key holding this device's stable CRDT node id.
  static const kNodeId = 'crdt.nodeId';

  /// File name of the persisted log, used by the io factory.
  static const logFileName = 'home_inventory.json';

  /// Builds a record whose clocks come from the item's own [Item.updatedAt]
  /// rather than "now".
  ///
  /// Every path that *restores* items the user already had — a file import,
  /// a backup recovery — must use this. Stamping "now" would make the
  /// restored copy outrank the same item on every other device, so a device
  /// recovering from a backup would silently overwrite newer edits made
  /// elsewhere. Seeding from real edit time makes a restore lose to genuinely
  /// newer data, which is what a restore should do.
  static Record recordAtItemTime(Item item, String nodeId) => Record(
    id: item.id,
    fields: _fieldsFor(
      item,
      Hlc(
        wallTimeMs: item.updatedAt.millisecondsSinceEpoch,
        counter: 0,
        nodeId: nodeId,
      ),
    ),
  );

  /// This device's CRDT node id.
  String get nodeId => _nodeId;

  /// Fires after every successful write. Emits `void` — pull data on demand.
  Stream<void> get changes => _store.changes;

  /// Opens (or creates) the inventory log backed by [persistence].
  ///
  /// Prunes ancient adjustments before returning, and *before* anything can
  /// push, so a device never re-uploads history it has already aged out.
  static Future<ItemRepository> openWith({
    required LogPersistence persistence,
    required String nodeId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final store = LogStore(persistence: persistence, nodeId: nodeId);
    final loaded = await store.load();
    final pruned = dropAncientAdjustments(loaded, at);
    if (pruned.length != loaded.length) await store.replaceAll(pruned);
    final repository = ItemRepository._(store, nodeId);
    await repository.runLocationMigration(now: at);
    return repository;
  }

  /// Folds any legacy `room`/`container` strings into [Location] records.
  ///
  /// Idempotent and convergent — see `planLocationMigration` for why — so it
  /// is safe to call on every open and after every sync. It must run after a
  /// sync too, not only on load: a peer still on the old build pushes items
  /// that carry the strings and no `location_id`, and those need folding on
  /// arrival or they stay invisible in the tree.
  ///
  /// Deliberately *not* run inside `syncLog`'s `decode` hook, unlike pruning.
  /// Pruning removes records; this one adds them, and adding inside `decode`
  /// would grow the merge input on every tick.
  Future<void> runLocationMigration({DateTime? now}) async {
    final plan = planLocationMigration(
      _liveItems(),
      _liveLocations(),
      now ?? DateTime.now(),
    );
    if (plan.isEmpty) return;
    for (final location in plan.locations) {
      await _upsertFields(
        location.id,
        _fieldsForLocation(location, _store.nextHlc()),
      );
    }
    for (final entry in plan.itemLocationIds.entries) {
      await _upsertFields(entry.key, {
        _fLocationId: (entry.value, _store.nextHlc()),
      });
    }
  }

  /// Opens a transient in-memory log; intended for tests.
  static Future<ItemRepository> openInMemory({String nodeId = 'test-node'}) =>
      openWith(persistence: _MemoryPersistence(), nodeId: nodeId);

  /// Closes the underlying store. The repository is unusable afterwards.
  Future<void> close() => _store.close();

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Iterable<Item> _liveItems() =>
      _store.values.where((r) => !r.deleted && isItemRecord(r)).map(_toItem);

  Iterable<Location> _liveLocations() => _store.values
      .where((r) => !r.deleted && isLocationRecord(r))
      .map(_toLocation);

  static int Function(Item, Item) _comparatorFor(ItemSort sort) =>
      switch (sort) {
        ItemSort.updatedDesc => (a, b) => b.updatedAt.compareTo(a.updatedAt),
        ItemSort.createdDesc => (a, b) => b.createdAt.compareTo(a.createdAt),
        ItemSort.nameAsc => _byName,
        ItemSort.quantityAsc => (a, b) {
          final byQuantity = a.quantity.compareTo(b.quantity);
          return byQuantity != 0 ? byQuantity : _byName(a, b);
        },
        ItemSort.locationAsc => (a, b) {
          final byRoom = a.room.toLowerCase().compareTo(b.room.toLowerCase());
          if (byRoom != 0) return byRoom;
          final byContainer = a.container.toLowerCase().compareTo(
            b.container.toLowerCase(),
          );
          return byContainer != 0 ? byContainer : _byName(a, b);
        },
        ItemSort.expiringFirst => (a, b) {
          final left = a.bestBefore;
          final right = b.bestBefore;
          if (left == null && right == null) return _byName(a, b);
          if (left == null) return 1;
          if (right == null) return -1;
          final byDate = left.compareTo(right);
          return byDate != 0 ? byDate : _byName(a, b);
        },
        ItemSort.lowStockFirst => (a, b) {
          final byState = _stockRank(a).compareTo(_stockRank(b));
          if (byState != 0) return byState;
          final byQuantity = a.quantity.compareTo(b.quantity);
          return byQuantity != 0 ? byQuantity : _byName(a, b);
        },
      };

  static int _byName(Item a, Item b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static int _stockRank(Item item) => switch (item.stockState) {
    StockState.out => 0,
    StockState.low => 1,
    StockState.ok => 2,
  };

  Stream<T> _watch<T>(T Function() compute) {
    StreamSubscription<void>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(compute());
        sub = _store.changes.listen((_) => controller.add(compute()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}

/// The cheapest possible [LogPersistence]: a string in memory. Used by
/// [ItemRepository.openInMemory] so tests never touch a real file.
class _MemoryPersistence implements LogPersistence {
  String? _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}
