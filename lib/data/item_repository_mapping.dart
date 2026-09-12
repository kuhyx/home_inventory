/// Encoding and decoding between CRDT records and the app's models.
///
/// A `part` of the repository rather than its own library: these are the wire
/// names and the field readers, and a second writer that disagreed about
/// either would corrupt the log rather than fail to compile. Keeping them in
/// the repository's private scope means only the repository can write them.
part of 'item_repository.dart';

// Item field names. Snake_case to match the other apps' wire formats.
const _fName = 'name';
const _fQuantity = 'quantity';
const _fUnit = 'unit';
const _fLocationId = 'location_id';
const _fRoom = 'room';
const _fContainer = 'container';
const _fCategory = 'category';
const _fLowStockAt = 'low_stock_at';
const _fBestBefore = 'best_before';
const _fWanted = 'wanted';
const _fSellable = 'sellable';
const _fNotes = 'notes';
const _fCreatedAt = 'created_at';
const _fUpdatedAt = 'updated_at';

// Barcode field names. `item_id` is shared with adjustments on purpose:
// both answer "which item does this record belong to".
const _fCode = 'code';
const _fAmount = 'amount';

// Adjustment field names.
const _fItemId = 'item_id';
const _fDelta = 'delta';
const _fSource = 'source';

// Location field names.
const _fParentId = 'parent_id';
const _fSortKey = 'sort_key';

Map<String, Field> _fieldsFor(Item item, Hlc hlc) => {
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

Map<String, Field> _fieldsForLocation(Location location, Hlc hlc) => {
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
double _num(Object? value, double fallback) =>
    (value as num?)?.toDouble() ?? fallback;

double? _nullableNum(Object? value) => (value as num?)?.toDouble();

String _str(Object? value) => value is String ? value : '';

/// Reads an optional stored timestamp.
///
/// Unlike [_time] this keeps null rather than falling back to the epoch: an
/// absent best-before date means "never goes off", and an epoch fallback
/// would render every undated screwdriver as expired since 1970.
DateTime? _nullableTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

DateTime _time(Object? value) {
  if (value is! String) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
