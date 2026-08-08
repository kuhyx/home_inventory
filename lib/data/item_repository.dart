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
  static const _fLocationId = 'location_id';
  static const _fRoom = 'room';
  static const _fContainer = 'container';
  static const _fCategory = 'category';
  static const _fLowStockAt = 'low_stock_at';
  static const _fBestBefore = 'best_before';
  static const _fWanted = 'wanted';
  static const _fSellable = 'sellable';
  static const _fNotes = 'notes';
  static const _fCreatedAt = 'created_at';
  static const _fUpdatedAt = 'updated_at';

  // Barcode field names. `item_id` is shared with adjustments on purpose:
  // both answer "which item does this record belong to".
  static const _fCode = 'code';
  static const _fAmount = 'amount';

  // Adjustment field names.
  static const _fItemId = 'item_id';
  static const _fDelta = 'delta';
  static const _fSource = 'source';

  // Location field names.
  static const _fParentId = 'parent_id';
  static const _fSortKey = 'sort_key';

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
    DateTime? asOf,
  }) {
    final items =
        _liveItems().where((item) => filter.matches(item, asOf: asOf)).toList()
          ..sort(_comparatorFor(sort));
    return items;
  }

  /// [listItems] as a stream that re-emits on every write.
  ///
  /// [asOf] is left null by the live screens on purpose: a freshness facet
  /// then re-reads the clock on each emission rather than pinning the date
  /// the stream happened to be opened on, so an app left running overnight
  /// does not keep yesterday's answer.
  Stream<List<Item>> watchItems({
    ItemSort sort = ItemSort.updatedDesc,
    ItemFilter filter = const ItemFilter(),
    DateTime? asOf,
  }) => _watch(() => listItems(sort: sort, filter: filter, asOf: asOf));

  /// The item with [id], or null if absent or deleted.
  Item? item(String id) {
    final record = _store.get(id);
    if (record == null || record.deleted) return null;
    if (!isItemRecord(record)) return null;
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

  /// Everything that belongs on the shopping list.
  ///
  /// This is a **union** — not fully stocked *or* explicitly wanted — which is
  /// why it cannot be expressed as an [ItemFilter]: filter facets are
  /// AND-combined, so `stock: {low, out}` plus `flags: {wanted}` would demand
  /// both and quietly hide the plain "I want one of these" entries.
  List<Item> listToBuy({ItemSort sort = ItemSort.lowStockFirst}) =>
      (_liveItems().where((item) => item.needsBuying).toList())
        ..sort(_comparatorFor(sort));

  /// [listToBuy] as a stream that re-emits on every write.
  Stream<List<Item>> watchToBuy({ItemSort sort = ItemSort.lowStockFirst}) =>
      _watch(() => listToBuy(sort: sort));

  // ---------------------------------------------------------------------
  // Barcodes
  // ---------------------------------------------------------------------

  /// The item and amount [code] stocks, or null when the code is unknown.
  ///
  /// A direct id lookup rather than a scan of the log: [BarcodeLink.recordId]
  /// makes the record id a pure function of the code, which is what keeps a
  /// scan O(1) at the till-side moment when the user is standing in the
  /// kitchen holding a bag.
  BarcodeLink? barcodeFor(String code) {
    final normalized = BarcodeLink.normalizeBarcode(code);
    if (normalized.isEmpty) return null;
    final record = _store.get(BarcodeLink.recordId(normalized));
    if (record == null || record.deleted || !isBarcodeRecord(record)) {
      return null;
    }
    final itemId = record.fields[_fItemId]?.$1;
    if (itemId is! String) return null;
    return BarcodeLink(
      code: normalized,
      itemId: itemId,
      amount: _num(record.fields[_fAmount]?.$1, 1),
      unit: _str(record.fields[_fUnit]?.$1),
    );
  }

  /// Every code that stocks [itemId], in scan order.
  List<BarcodeLink> barcodesFor(String itemId) {
    final links = <BarcodeLink>[];
    for (final record in _store.values) {
      if (record.deleted || !isBarcodeRecord(record)) continue;
      final owner = record.fields[_fItemId]?.$1;
      final code = record.fields[_fCode]?.$1;
      if (owner != itemId || code is! String) continue;
      links.add(
        BarcodeLink(
          code: code,
          itemId: itemId,
          amount: _num(record.fields[_fAmount]?.$1, 1),
          unit: _str(record.fields[_fUnit]?.$1),
        ),
      );
    }
    links.sort((a, b) => a.code.compareTo(b.code));
    return List.unmodifiable(links);
  }

  /// Points [code] at [itemId], replacing any previous mapping for that code.
  ///
  /// Returns the stored link, or null when the code is blank or [amount] is
  /// not positive — a link that adds nothing is one the user would scan twice
  /// and then assume the app was broken.
  Future<BarcodeLink?> linkBarcode({
    required String code,
    required String itemId,
    double amount = 1,
    String unit = '',
  }) async {
    final normalized = BarcodeLink.normalizeBarcode(code);
    if (normalized.isEmpty || amount <= 0) return null;
    final hlc = _store.nextHlc();
    await _store.upsert(
      Record(
        id: BarcodeLink.recordId(normalized),
        fields: {
          kTypeField: (kTypeBarcode, hlc),
          _fCode: (normalized, hlc),
          _fItemId: (itemId, hlc),
          _fAmount: (amount, hlc),
          _fUnit: (unit, hlc),
        },
      ),
    );
    return BarcodeLink(
      code: normalized,
      itemId: itemId,
      amount: amount,
      unit: unit,
    );
  }

  /// Forgets [code].
  Future<void> unlinkBarcode(String code) =>
      _store.delete(BarcodeLink.recordId(BarcodeLink.normalizeBarcode(code)));

  /// Applies one scan of [code] as a quantity change of the linked amount.
  ///
  /// Returns the updated item, or null when the code is unknown or its item
  /// has since been deleted. [source] is the caller's, never inferred: a scan
  /// at the shopping-bag-unpacking moment is a restock and a scan at the
  /// point of eating something is use, and getting that wrong is the one
  /// mistake that silently corrupts the rate hint.
  Future<Item?> applyScan(
    String code, {
    required AdjustmentSource source,
    DateTime? now,
  }) async {
    final link = barcodeFor(code);
    if (link == null) return null;
    final delta = source == AdjustmentSource.use ? -link.amount : link.amount;
    return adjustQuantity(link.itemId, delta, source, now: now);
  }

  /// Everything already past its best-before date or close to it, soonest
  /// first.
  ///
  /// A repository method rather than an [ItemFilter] preset for the same
  /// reason [listToBuy] is one: it is a **union** of two freshness states,
  /// and facets are AND-combined.
  List<Item> listExpiring({DateTime? now}) {
    final at = now ?? DateTime.now();
    return _liveItems()
        .where(
          (item) => switch (item.freshnessAt(at)?.state) {
            FreshnessState.expired || FreshnessState.dueSoon => true,
            FreshnessState.fresh || null => false,
          },
        )
        .toList()
      ..sort(_comparatorFor(ItemSort.expiringFirst));
  }

  /// [listExpiring] as a stream that re-emits on every write.
  Stream<List<Item>> watchExpiring({DateTime? now}) =>
      _watch(() => listExpiring(now: now));

  /// Everything flagged as sellable.
  List<Item> listSellable({ItemSort sort = ItemSort.nameAsc}) =>
      (_liveItems().where((item) => item.sellable).toList())
        ..sort(_comparatorFor(sort));

  /// [listSellable] as a stream that re-emits on every write.
  Stream<List<Item>> watchSellable({ItemSort sort = ItemSort.nameAsc}) =>
      _watch(() => listSellable(sort: sort));

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

  // ---------------------------------------------------------------------
  // Locations
  // ---------------------------------------------------------------------

  /// Every live place, in no particular order.
  List<Location> listLocations() => _liveLocations().toList();

  /// [listLocations] as a stream that re-emits on every write.
  Stream<List<Location>> watchLocations() => _watch(listLocations);

  /// The place with [id], or null if absent or deleted.
  Location? location(String id) {
    final record = _store.get(id);
    if (record == null || record.deleted) return null;
    if (!isLocationRecord(record)) return null;
    return _toLocation(record);
  }

  /// The whole place tree, with item counts, deepest structure intact.
  ///
  /// **Cycles are handled here, not only at the writer.** Under CRDT merge a
  /// cycle is not hypothetical: this device moves A under B while another
  /// moves B under A, each write wins its own field, and the merged graph has
  /// a two-node loop that a naive walk would follow forever. So the tree is
  /// built by walking down from the roots with a visited set, and anything
  /// never reached — a cycle, or a child of a deleted parent — is re-attached
  /// at the top level rather than vanishing. That rule is a pure function of
  /// the merged log, so both devices show the same tree.
  List<LocationTreeNode> locationTree() {
    final locations = {for (final l in _liveLocations()) l.id: l};

    final direct = <String, int>{};
    for (final item in _liveItems()) {
      if (item.locationId.isEmpty) continue;
      if (!locations.containsKey(item.locationId)) continue;
      direct.update(item.locationId, (n) => n + 1, ifAbsent: () => 1);
    }

    final childIds = <String?, List<String>>{};
    for (final entry in locations.entries) {
      final parent = entry.value.parentId;
      // A parent that is gone (tombstoned, or never synced) makes this a root,
      // so deleting a cupboard never takes its shelves out of sight with it.
      final resolved = parent != null && locations.containsKey(parent)
          ? parent
          : null;
      childIds.putIfAbsent(resolved, () => <String>[]).add(entry.key);
    }

    final visited = <String>{};

    List<LocationTreeNode> build(String? parentId, int depth) {
      final ids = childIds[parentId] ?? const <String>[];
      final nodes = <LocationTreeNode>[];
      for (final id in ids) {
        if (!visited.add(id)) continue;
        final children = build(id, depth + 1);
        final own = direct[id] ?? 0;
        nodes.add(
          LocationTreeNode(
            location: locations[id]!,
            children: children,
            directItemCount: own,
            totalItemCount:
                own + children.fold<int>(0, (sum, c) => sum + c.totalItemCount),
            depth: depth,
          ),
        );
      }
      return nodes..sort(_bySortKeyThenName);
    }

    final roots = build(null, 0);

    // Anything unreachable from a root is in a cycle. Re-root it so the user
    // can still see and fix it; dropping it would look like data loss.
    final stranded = locations.keys.where((id) => !visited.contains(id));
    for (final id in stranded.toList()) {
      if (visited.contains(id)) continue;
      visited.add(id);
      final children = build(id, 1);
      final own = direct[id] ?? 0;
      roots.add(
        LocationTreeNode(
          location: locations[id]!,
          children: children,
          directItemCount: own,
          totalItemCount:
              own + children.fold<int>(0, (sum, c) => sum + c.totalItemCount),
          depth: 0,
        ),
      );
    }

    return roots..sort(_bySortKeyThenName);
  }

  /// [locationTree] as a stream that re-emits on every write.
  Stream<List<LocationTreeNode>> watchLocationTree() => _watch(locationTree);

  /// The chain of names from the top down to [locationId].
  ///
  /// Empty when the id is unknown. Stops at a cycle rather than looping.
  List<String> pathOf(String locationId) {
    final names = <String>[];
    final seen = <String>{};
    var current = location(locationId);
    while (current != null && seen.add(current.id)) {
      names.insert(0, current.name);
      final parent = current.parentId;
      current = parent == null ? null : location(parent);
    }
    return names;
  }

  /// [pathOf] joined for display, e.g. `korytarz › szafka z lewej`.
  String pathLabel(String locationId) => pathOf(locationId).join(' › ');

  /// Where [item] is, as one label.
  ///
  /// Falls back to the legacy strings for an item the migration has not
  /// reached — one pulled in mid-sync from a device still on the old build,
  /// which would otherwise read as "nowhere" until the next app start.
  String locationLabelFor(Item item) => item.locationId.isEmpty
      ? item.legacyLocation
      : pathLabel(item.locationId);

  /// [locationId] plus every place beneath it.
  ///
  /// What "show me everything in the hallway" means: filtering by one id alone
  /// would miss everything on its shelves. Cycle-safe via the visited set.
  Set<String> subtreeIds(String locationId) {
    final byParent = <String, List<String>>{};
    for (final l in _liveLocations()) {
      final parent = l.parentId;
      if (parent != null) byParent.putIfAbsent(parent, () => []).add(l.id);
    }
    final ids = <String>{};
    void walk(String id) {
      // The visited set is what makes a merged-in cycle terminate here.
      if (!ids.add(id)) return;
      (byParent[id] ?? const <String>[]).forEach(walk);
    }

    walk(locationId);
    return ids;
  }

  /// Creates a place called [name] under [parentId].
  ///
  /// The id is derived, not minted, so this is idempotent: creating "Garage"
  /// twice — here and on another device, offline — yields one record, not two.
  /// Returns the existing place when it is already there.
  Future<Location> createLocation({
    required String name,
    String? parentId,
    double sortKey = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = derivedLocationId(parentId, name);
    final existing = location(id);
    if (existing != null) return existing;
    final created = Location(
      id: id,
      name: name.trim(),
      parentId: parentId,
      sortKey: sortKey,
      createdAt: at,
      updatedAt: at,
    );
    await _upsertFields(id, _fieldsForLocation(created, _store.nextHlc()));
    return created;
  }

  /// Whether [parentId] already holds a child called [name].
  ///
  /// Derived ids mean two same-named siblings would collapse onto one record,
  /// so the create/rename UI has to refuse the collision up front.
  bool hasChildNamed(String? parentId, String name, {String? ignoringId}) {
    final folded = foldKey(name);
    return _liveLocations().any(
      (l) =>
          l.id != ignoringId &&
          l.parentId == parentId &&
          foldKey(l.name) == folded,
    );
  }

  /// Renames [id]. The record id deliberately does not change with it.
  Future<void> renameLocation(String id, String name, {DateTime? now}) async {
    if (location(id) == null) return;
    final at = now ?? DateTime.now();
    final hlc = _store.nextHlc();
    await _upsertFields(id, {
      _fName: (name.trim(), hlc),
      _fUpdatedAt: (at.toIso8601String(), hlc),
    });
  }

  /// Re-parents [id] under [newParentId], or to the top level when null.
  ///
  /// Refuses a move into the mover's own subtree, which would orphan the
  /// branch. That check is the user-facing guard only — it cannot see a
  /// concurrent move on another device, which is why [locationTree] breaks
  /// cycles on read as well.
  Future<bool> moveLocation(
    String id,
    String? newParentId, {
    DateTime? now,
  }) async {
    if (location(id) == null) return false;
    if (id == newParentId) return false;
    if (newParentId != null && subtreeIds(id).contains(newParentId)) {
      return false;
    }
    final at = now ?? DateTime.now();
    final hlc = _store.nextHlc();
    await _upsertFields(id, {
      _fParentId: (newParentId, hlc),
      _fUpdatedAt: (at.toIso8601String(), hlc),
    });
    return true;
  }

  /// Deletes [id], leaving its children and items in place.
  ///
  /// Never cascades. A sticky CRDT delete plus a cascade means one mis-tap on
  /// a phone removes a whole wing of the tree on every device, with no undo;
  /// orphaned children resurface at the top level instead, and items filed in
  /// the deleted place read as unfiled.
  Future<void> deleteLocation(String id) => _store.delete(id);

  /// How many live items are filed at exactly [locationId].
  int itemCountAt(String locationId) =>
      _liveItems().where((i) => i.locationId == locationId).length;

  static int _bySortKeyThenName(LocationTreeNode a, LocationTreeNode b) {
    final bySort = a.location.sortKey.compareTo(b.location.sortKey);
    if (bySort != 0) return bySort;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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

  /// Stamps only [changed] on the record with [id], keeping every other
  /// field's existing clock.
  ///
  /// The partial-write primitive behind every targeted edit. Writing a whole
  /// record instead re-stamps every field with a fresh clock, which makes this
  /// device's stale copy of an untouched field outrank a newer edit made
  /// elsewhere — so renaming a place here would silently revert a move made on
  /// the phone. Spreading the existing fields is what keeps per-field
  /// last-writer-wins actually per-field.
  Future<void> _upsertFields(String id, Map<String, Field> changed) async {
    final existing = _store.get(id);
    await _store.upsert(
      Record(
        id: id,
        fields: {...?existing?.fields, ...changed},
      ),
    );
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

  /// The whole log as JSON text, for a manual backup.
  ///
  /// Deliberately the raw CRDT log rather than a prettied list of items: the
  /// quantity history and every field's clock come with it, so re-importing a
  /// backup is a lossless merge instead of a reset to whatever the file said.
  String exportJson() => logToJson(exportLog());

  /// Merges a backup produced by [exportJson] into the local log.
  ///
  /// A **merge**, never a replace. Restoring a month-old backup must not undo
  /// this month's edits, and per-record clocks already decide which side of
  /// each field wins.
  ///
  /// Throws [FormatException] on text that is not JSON. Malformed-but-valid
  /// JSON surfaces as a `TypeError` from `logFromJson`, so the settings
  /// screen's import action catches both rather than only `Exception`.
  Future<void> importJson(String text) => importLog(logFromJson(text));

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
    _fLocationId: (item.locationId, hlc),
    _fRoom: (item.room, hlc),
    _fContainer: (item.container, hlc),
    _fCategory: (item.category, hlc),
    _fLowStockAt: (item.lowStockAt, hlc),
    _fBestBefore: (item.bestBefore?.toIso8601String(), hlc),
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
      locationId: _str(fields[_fLocationId]?.$1),
      room: _str(fields[_fRoom]?.$1),
      container: _str(fields[_fContainer]?.$1),
      category: _str(fields[_fCategory]?.$1),
      lowStockAt: _nullableNum(fields[_fLowStockAt]?.$1),
      bestBefore: _nullableTime(fields[_fBestBefore]?.$1),
      wanted: fields[_fWanted]?.$1 == true,
      sellable: fields[_fSellable]?.$1 == true,
      notes: _str(fields[_fNotes]?.$1),
      createdAt: _time(fields[_fCreatedAt]?.$1),
      updatedAt: _time(fields[_fUpdatedAt]?.$1),
    );
  }

  static Map<String, Field> _fieldsForLocation(Location location, Hlc hlc) => {
    kTypeField: (kTypeLocation, hlc),
    _fName: (location.name, hlc),
    _fParentId: (location.parentId, hlc),
    _fSortKey: (location.sortKey, hlc),
    _fCreatedAt: (location.createdAt.toIso8601String(), hlc),
    _fUpdatedAt: (location.updatedAt.toIso8601String(), hlc),
  };

  Location _toLocation(Record record) {
    final fields = record.fields;
    final parent = fields[_fParentId]?.$1;
    return Location(
      id: record.id,
      name: _str(fields[_fName]?.$1),
      // Anything that is not a non-empty string reads as "top level", so a
      // null, a missing field and a blank all mean the same thing.
      parentId: parent is String && parent.isNotEmpty ? parent : null,
      sortKey: _num(fields[_fSortKey]?.$1, 0),
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

  /// Reads an optional stored timestamp.
  ///
  /// Unlike [_time] this keeps null rather than falling back to the epoch: an
  /// absent best-before date means "never goes off", and an epoch fallback
  /// would render every undated screwdriver as expired since 1970.
  static DateTime? _nullableTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static DateTime _time(Object? value) {
    if (value is! String) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Iterable<Item> _liveItems() =>
      _store.values.where((r) => !r.deleted && isItemRecord(r)).map(_toItem);

  Iterable<Location> _liveLocations() => _store.values
      .where((r) => !r.deleted && isLocationRecord(r))
      .map(_toLocation);

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
