/// The core domain type: one kind of thing the user owns, wherever it lives.
library;

/// How much of an [Item] is on hand, relative to its own threshold.
///
/// Deliberately derived rather than stored: a stored flag would be a second
/// source of truth that a concurrent quantity edit on another device could
/// leave stale.
enum StockState {
  /// Above the threshold, or no threshold set.
  ok,

  /// At or below [Item.lowStockAt] — time to buy more.
  low,

  /// None left at all.
  out,
}

/// Renders a quantity without a pointless trailing `.0`.
///
/// Quantities are [double] so "2.5 kg of flour" is expressible, but most
/// items are countable, and "4.0 cables" reads as a bug.
String formatQuantity(double quantity) => quantity == quantity.roundToDouble()
    ? quantity.toStringAsFixed(0)
    : quantity.toString();

/// One kind of thing the user owns.
///
/// Immutable; edits go through [copyWith] and are persisted by
/// `ItemRepository` as a per-field last-writer-wins CRDT record. That per-field
/// granularity is why the fields here are flat scalars rather than nested
/// objects: two devices editing `quantity` and `room` concurrently must both
/// win, which only works if they are separate CRDT fields.
class Item {
  /// Creates an item. Every field is required so a new persisted field can
  /// never be silently forgotten at a call site.
  const Item({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.room,
    required this.container,
    required this.category,
    required this.lowStockAt,
    required this.wanted,
    required this.sellable,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable identifier (a uuid v4), also the CRDT record id.
  final String id;

  /// What the thing is, e.g. `USB-C cable`. The primary search key.
  final String name;

  /// How many/much is on hand.
  final double quantity;

  /// Unit of [quantity], e.g. `kg`. Empty means a plain count.
  final String unit;

  /// Coarse location, e.g. `Kitchen`. Free text, autocompleted from existing
  /// values rather than constrained to an enum.
  final String room;

  /// Fine location within [room], e.g. `Top drawer left`.
  final String container;

  /// Free-text grouping, e.g. `Cables`. Free text on purpose: the span from
  /// books to toilet paper has no closed set, and an enum would grow an
  /// `other` bucket that swallows everything.
  final String category;

  /// Quantity at or below which this item counts as [StockState.low].
  ///
  /// Null means "never warn me" — the common case, since only consumables
  /// need a threshold.
  final double? lowStockAt;

  /// Whether the user wants this but does not have it — it belongs on the
  /// shopping list regardless of [quantity].
  final bool wanted;

  /// Whether the user would happily sell or give this away.
  final bool sellable;

  /// Anything else: model numbers, sizes, an asking price, "behind the
  /// router", "borrowed from J".
  final String notes;

  /// When the item was first added.
  final DateTime createdAt;

  /// When the item was last edited. Drives the default sort, and is the clock
  /// a restore path must stamp records with (never "now").
  final DateTime updatedAt;

  /// Whether this item is out, low, or fine.
  StockState get stockState {
    if (quantity <= 0) return StockState.out;
    final threshold = lowStockAt;
    if (threshold != null && quantity <= threshold) return StockState.low;
    return StockState.ok;
  }

  /// Human-readable place, e.g. `Kitchen › Top drawer left`.
  ///
  /// Skips empty parts, so an item with only a room reads as just the room
  /// rather than a dangling separator.
  String get location =>
      [room, container].where((part) => part.isNotEmpty).join(' › ');

  /// Whether this item belongs on the shopping list: anything not fully
  /// stocked, plus anything explicitly [wanted].
  bool get needsBuying => stockState != StockState.ok || wanted;

  /// Returns a copy with the given fields replaced.
  ///
  /// A null argument means "leave unchanged", so clearing the nullable
  /// [lowStockAt] needs the explicit [clearLowStockAt] flag.
  Item copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? room,
    String? container,
    String? category,
    double? lowStockAt,
    bool clearLowStockAt = false,
    bool? wanted,
    bool? sellable,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Item(
    id: id,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    room: room ?? this.room,
    container: container ?? this.container,
    category: category ?? this.category,
    lowStockAt: clearLowStockAt ? null : (lowStockAt ?? this.lowStockAt),
    wanted: wanted ?? this.wanted,
    sellable: sellable ?? this.sellable,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  String toString() =>
      'Item(id: $id, name: $name, quantity: $quantity $unit, '
      'location: $location)';
}
