/// Local-first persistence and querying for the inventory.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/record_types.dart';
import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/inventory_summary.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/item_filter.dart';
import 'package:home_inventory/models/location_node.dart';
import 'package:home_inventory/models/rate_hint.dart';

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

  // Item field names. Snake_case to match the other apps' wire formats.
  static const _fName = 'name';
  static const _fQuantity = 'quantity';
  static const _fUnit = 'unit';
  static const _fRoom = 'room';
  static const _fContainer = 'container';
  static const _fCategory = 'category';
  static const _fLowStockAt = 'low_stock_at';
  static const _fWanted = 'wanted';
  static const _fSellable = 'sellable';
  static const _fNotes = 'notes';
  static const _fCreatedAt = 'created_at';
  static const _fUpdatedAt = 'updated_at';

  // Adjustment field names.
  static const _fItemId = 'item_id';
  static const _fDelta = 'delta';
  static const _fSource = 'source';

  /// SharedPreferences key holding this device's stable CRDT node id.
  static const kNodeId = 'crdt.nodeId';

  /// File name of the persisted log, used by the io factory.
  static const logFileName = 'home_inventory.json';

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
    final store = LogStore(persistence: persistence, nodeId: nodeId);
    final loaded = await store.load();
    final pruned = dropAncientAdjustments(loaded, now ?? DateTime.now());
    if (pruned.length != loaded.length) await store.replaceAll(pruned);
    return ItemRepository._(store, nodeId);
  }

  /// Opens a transient in-memory log; intended for tests.
  static Future<ItemRepository> openInMemory({
    String nodeId = 'test-node',
  }) => openWith(persistence: _MemoryPersistence(), nodeId: nodeId);

  /// Closes the underlying store. The repository is unusable afterwards.
  Future<void> close() => _store.close();

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  /// Every live item, filtered and sorted.
  List<Item> listItems({
    ItemSort sort = ItemSort.updatedDesc,
    ItemFilter filter = const ItemFilter(),
  }) {
    final items = _liveItems().where(filter.matches).toList()
      ..sort(_comparatorFor(sort));
    return items;
  }

  /// [listItems] as a stream that re-emits on every write.
  Stream<List<Item>> watchItems({
    ItemSort sort = ItemSort.updatedDesc,
    ItemFilter filter = const ItemFilter(),
  }) => _watch(() => listItems(sort: sort, filter: filter));

  /// The item with [id], or null if absent or deleted.
  Item? item(String id) {
    final record = _store.get(id);
    if (record == null || record.deleted) return null;
    if (isAdjustmentRecord(record)) return null;
    return _toItem(record);
  }

  /// [item] as a stream that re-emits on every write.
  Stream<Item?> watchItem(String id) => _watch(() => item(id));

  /// Headline counts across the whole inventory.
  InventorySummary summary() {
    final items = _liveItems().toList();
    var low = 0;
    var out = 0;
    var wanted = 0;
    var sellable = 0;
    var toBuy = 0;
    for (final item in items) {
      switch (item.stockState) {
        case StockState.low:
          low++;
        case StockState.out:
          out++;
        case StockState.ok:
          break;
      }
      if (item.wanted) wanted++;
      if (item.sellable) sellable++;
      if (item.needsBuying) toBuy++;
    }
    return InventorySummary(
      total: items.length,
      low: low,
      out: out,
      wanted: wanted,
      sellable: sellable,
      toBuy: toBuy,
    );
  }

  /// [summary] as a stream that re-emits on every write.
  Stream<InventorySummary> watchSummary() => _watch(summary);

  // ---------------------------------------------------------------------
  // Autocomplete sources
  // ---------------------------------------------------------------------

  /// Rooms already in use, most-used first then alphabetically.
  ///
  /// Ordering by usage is what makes free-text locations workable: the room
  /// you file things in most is the first suggestion, so the common case is
  /// a tap rather than typing — which is also what keeps casing consistent.
  List<String> knownRooms() => _rankedValues((item) => item.room);

  /// Containers already in use, optionally narrowed to one [room].
  List<String> knownContainers({String? room}) {
    final wanted = room?.toLowerCase();
    return _rankedValues(
      (item) => item.container,
      where: wanted == null
          ? null
          : (item) => item.room.toLowerCase() == wanted,
    );
  }

  /// Categories already in use, most-used first.
  List<String> knownCategories() => _rankedValues((item) => item.category);

  /// Units already in use, most-used first.
  List<String> knownUnits() => _rankedValues((item) => item.unit);

  /// The room → container tree, with item counts, for the locations screen.
  List<LocationNode> locationTree() {
    final byRoom = <String, Map<String, int>>{};
    for (final item in _liveItems()) {
      byRoom
          .putIfAbsent(item.room, () => <String, int>{})
          .update(item.container, (count) => count + 1, ifAbsent: () => 1);
    }
    final nodes =
        byRoom.entries.map((entry) {
          final containers =
              entry.value.entries
                  .map(
                    (c) => ContainerNode(name: c.key, itemCount: c.value),
                  )
                  .toList()
                ..sort(_byCountThenName);
          final total = entry.value.values.fold<int>(0, (sum, n) => sum + n);
          return LocationNode(
            room: entry.key,
            containers: containers,
            itemCount: total,
          );
        }).toList()..sort((a, b) {
          final byCount = b.itemCount.compareTo(a.itemCount);
          return byCount != 0 ? byCount : a.room.compareTo(b.room);
        });
    return nodes;
  }

  static int _byCountThenName(ContainerNode a, ContainerNode b) {
    final byCount = b.itemCount.compareTo(a.itemCount);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  }

  // ---------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------

  /// Inserts a new item or updates the existing one with the same id.
  ///
  /// If [quantity] differs from what is stored, an [Adjustment] is appended
  /// too, attributed to [source] — defaulting to
  /// [AdjustmentSource.correction], because the only caller that reaches this
  /// with a changed quantity is the edit form, i.e. a recount. Getting that
  /// attribution wrong is the one mistake that silently corrupts the rate
  /// hint, so it is explicit here rather than inferred from the delta's sign.
  Future<void> upsert(
    Item item, {
    AdjustmentSource source = AdjustmentSource.correction,
  }) async {
    final previous = this.item(item.id);
    final delta = item.quantity - (previous?.quantity ?? 0);
    await _store.upsert(
      Record(id: item.id, fields: _fieldsFor(item, _store.nextHlc())),
    );
    if (delta != 0) {
      await _appendAdjustment(
        itemId: item.id,
        delta: delta,
        source: previous == null ? AdjustmentSource.initial : source,
        at: item.updatedAt,
      );
    }
  }

  /// Soft-deletes an item, leaving a sticky tombstone so the deletion
  /// survives a merge with a device that has not seen it yet.
  Future<void> delete(String id) => _store.delete(id);

  /// Applies a relative quantity change and records why.
  ///
  /// Returns the updated item, or null if [id] is unknown. A zero [delta]
  /// writes nothing at all — an empty adjustment would dilute the rate.
  Future<Item?> adjustQuantity(
    String id,
    double delta,
    AdjustmentSource source, {
    DateTime? now,
  }) async {
    final current = item(id);
    if (current == null || delta == 0) return current;
    final at = now ?? DateTime.now();
    // Clamp at zero: a negative quantity is not a state the physical world
    // has, and it would make `stockState` report `out` while the projection
    // divides by a negative headroom.
    final next = (current.quantity + delta).clamp(0.0, double.infinity);
    return _writeQuantity(current, next, source, at);
  }

  /// Sets an absolute quantity and records why.
  ///
  /// Returns the updated item, or null if [id] is unknown.
  Future<Item?> setQuantity(
    String id,
    double quantity,
    AdjustmentSource source, {
    DateTime? now,
  }) async {
    final current = item(id);
    if (current == null) return current;
    final next = quantity < 0 ? 0.0 : quantity;
    if (next == current.quantity) return current;
    return _writeQuantity(current, next, source, now ?? DateTime.now());
  }

  Future<Item> _writeQuantity(
    Item current,
    double next,
    AdjustmentSource source,
    DateTime at,
  ) async {
    final updated = current.copyWith(quantity: next, updatedAt: at);
    // Only `quantity` and `updated_at` get a fresh clock here; every other
    // field keeps the clock it was last written at. That is exactly why a
    // phone decrementing a count does not clobber a desktop edit to the same
    // item's location.
    final hlc = _store.nextHlc();
    final existing = _store.get(current.id);
    final fields = <String, Field>{
      ...?existing?.fields,
      _fQuantity: (next, hlc),
      _fUpdatedAt: (at.toIso8601String(), hlc),
    };
    await _store.upsert(Record(id: current.id, fields: fields));
    await _appendAdjustment(
      itemId: current.id,
      delta: next - current.quantity,
      source: source,
      at: at,
    );
    return updated;
  }

  Future<void> _appendAdjustment({
    required String itemId,
    required double delta,
    required AdjustmentSource source,
    required DateTime at,
  }) async {
    final hlc = _store.nextHlc();
    // The adjustment's id is derived from the clock that wrote it, which is
    // unique per device per tick — so it needs no uuid dependency here and
    // two devices can never collide.
    final id = 'adj-${hlc.toStr()}';
    await _store.upsert(
      Record(
        id: id,
        fields: {
          kTypeField: (kTypeAdjustment, hlc),
          _fItemId: (itemId, hlc),
          _fDelta: (delta, hlc),
          kAtField: (at.toIso8601String(), hlc),
          _fSource: (source.wire, hlc),
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // History and the rate projection
  // ---------------------------------------------------------------------

  /// Every recorded change to [itemId], oldest first.
  ///
  /// Scanned on demand rather than served from a maintained index. An index
  /// looks cheaper, but the store's change event is delivered
  /// asynchronously, so an index rebuilt from it is stale for a microtask
  /// after every write — and `rateHint` runs during a widget build, which is
  /// exactly when that window is open. A full scan is trivial at household
  /// scale and cannot be stale.
  List<Adjustment> historyFor(String itemId) {
    final history = <Adjustment>[];
    for (final record in _store.values) {
      if (record.deleted || !isAdjustmentRecord(record)) continue;
      final adjustment = _toAdjustment(record);
      if (adjustment == null || adjustment.itemId != itemId) continue;
      history.add(adjustment);
    }
    history.sort((a, b) => a.at.compareTo(b.at));
    return List.unmodifiable(history);
  }

  /// Projects when [itemId] will hit its low-stock threshold, or null when
  /// there is not enough evidence to say.
  ///
  /// Returning null — rather than a hedge, a spinner or an "unknown" label —
  /// is the correct output for insufficient data: `Item.lowStockAt` is the
  /// deterministic warner, so a quiet hint is a working hint.
  RateHint? rateHint(String itemId, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final target = item(itemId);
    if (target == null) return null;

    final uses = historyFor(itemId)
        .where((a) => a.source == AdjustmentSource.use && a.delta < 0)
        // A future-dated `at` means a misconfigured device clock; including
        // it would make the observed span negative or absurd.
        .where((a) => !a.at.isAfter(at))
        .where((a) => at.difference(a.at) <= RateWindow.window)
        .toList();
    if (uses.length < RateWindow.minSamples) return null;

    final first = uses.map((a) => a.at).reduce((a, b) => a.isBefore(b) ? a : b);
    // Span runs first-use → *now*, not first-use → last-use. Counting a
    // recent quiet stretch lowers the rate, i.e. reports more days left —
    // the conservative direction, and the honest one given the threshold is
    // what actually warns.
    final spanDays = at.difference(first).inMinutes / (60 * 24);
    if (spanDays < RateWindow.minSpanDays) return null;

    final consumed = uses.fold<double>(0, (sum, a) => sum + a.consumed);
    final perDay = consumed / spanDays;
    if (perDay <= 0) return null;

    final headroom = target.quantity - (target.lowStockAt ?? 0);
    // Already at or under the threshold: the stock badge is saying so, and a
    // projection of "0 days" alongside it is noise.
    if (headroom <= 0) return null;

    final daysLeft = headroom / perDay;
    if (daysLeft > RateWindow.maxDaysLeft) return null;
    return RateHint(
      perDay: perDay,
      daysLeft: daysLeft.floor(),
      sampleCount: uses.length,
    );
  }

  // ---------------------------------------------------------------------
  // Sync seam
  // ---------------------------------------------------------------------

  /// The whole log, to hand to `syncLog`.
  Log exportLog() => _store.snapshot();

  /// Merges [remote] into the local log.
  Future<void> importLog(Log remote) =>
      _store.replaceAll(mergeLogs(_store.snapshot(), remote));

  /// Replaces the whole log, e.g. with a post-merge result from `syncLog`.
  Future<void> replaceAll(Log merged) => _store.replaceAll(merged);

  /// Drops adjustments past the retention horizon, persisting only if
  /// something actually changed.
  Future<void> pruneHistory({DateTime? now}) async {
    final snapshot = _store.snapshot();
    final pruned = dropAncientAdjustments(snapshot, now ?? DateTime.now());
    if (pruned.length != snapshot.length) await _store.replaceAll(pruned);
  }

  // ---------------------------------------------------------------------
  // Record mapping
  // ---------------------------------------------------------------------

  static Map<String, Field> _fieldsFor(Item item, Hlc hlc) => {
    kTypeField: (kTypeItem, hlc),
    _fName: (item.name, hlc),
    _fQuantity: (item.quantity, hlc),
    _fUnit: (item.unit, hlc),
    _fRoom: (item.room, hlc),
    _fContainer: (item.container, hlc),
    _fCategory: (item.category, hlc),
    _fLowStockAt: (item.lowStockAt, hlc),
    _fWanted: (item.wanted, hlc),
    _fSellable: (item.sellable, hlc),
    _fNotes: (item.notes, hlc),
    _fCreatedAt: (item.createdAt.toIso8601String(), hlc),
    _fUpdatedAt: (item.updatedAt.toIso8601String(), hlc),
  };

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

  Item _toItem(Record record) {
    final fields = record.fields;
    return Item(
      id: record.id,
      name: _str(fields[_fName]?.$1),
      quantity: _num(fields[_fQuantity]?.$1, 0),
      unit: _str(fields[_fUnit]?.$1),
      room: _str(fields[_fRoom]?.$1),
      container: _str(fields[_fContainer]?.$1),
      category: _str(fields[_fCategory]?.$1),
      lowStockAt: _nullableNum(fields[_fLowStockAt]?.$1),
      wanted: fields[_fWanted]?.$1 == true,
      sellable: fields[_fSellable]?.$1 == true,
      notes: _str(fields[_fNotes]?.$1),
      createdAt: _time(fields[_fCreatedAt]?.$1),
      updatedAt: _time(fields[_fUpdatedAt]?.$1),
    );
  }

  Adjustment? _toAdjustment(Record record) {
    final fields = record.fields;
    final itemId = fields[_fItemId]?.$1;
    final at = fields[kAtField]?.$1;
    if (itemId is! String || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return Adjustment(
      id: record.id,
      itemId: itemId,
      delta: _num(fields[_fDelta]?.$1, 0),
      at: parsed,
      source: AdjustmentSource.fromWire(fields[_fSource]?.$1 as String?),
    );
  }

  /// Reads a stored number.
  ///
  /// Must never be `as double`. A double whose value is integral serializes
  /// to JSON as `1` and comes back as `int`, so a plain cast throws under
  /// `strict-casts` on any record that has round-tripped through storage or
  /// sync — which is every record, on the second run.
  static double _num(Object? value, double fallback) =>
      (value as num?)?.toDouble() ?? fallback;

  static double? _nullableNum(Object? value) => (value as num?)?.toDouble();

  static String _str(Object? value) => value is String ? value : '';

  static DateTime _time(Object? value) {
    if (value is! String) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Iterable<Item> _liveItems() => _store.values
      .where((r) => !r.deleted && !isAdjustmentRecord(r))
      .map(_toItem);

  List<String> _rankedValues(
    String Function(Item) select, {
    bool Function(Item)? where,
  }) {
    final counts = <String, int>{};
    for (final item in _liveItems()) {
      if (where != null && !where(item)) continue;
      final value = select(item);
      if (value.isEmpty) continue;
      counts.update(value, (n) => n + 1, ifAbsent: () => 1);
    }
    final values = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return values;
  }

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
