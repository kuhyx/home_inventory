/// Query shape for the item list: what to show, and in what order.
library;

import 'package:home_inventory/models/item.dart';
import 'package:meta/meta.dart';

/// A boolean item property the user can filter on.
enum ItemFlag {
  /// [Item.wanted] is set.
  wanted,

  /// [Item.sellable] is set.
  sellable,
}

/// How the item list is ordered.
enum ItemSort {
  /// Most recently edited first. The default — and what makes a freshly
  /// synced item appear at the top without touching a control.
  updatedDesc,

  /// A-Z by name, for reference browsing.
  nameAsc,

  /// Newest first.
  createdDesc,

  /// Scarcest first.
  quantityAsc,

  /// Room, then container, then name — the order you'd walk the flat in.
  locationAsc,

  /// Out, then low, then fine; scarcest first within each band.
  lowStockFirst,
}

/// An AND-combined set of list restrictions.
///
/// Each facet is independent and empty means "any", so the default instance
/// shows everything. Within one facet, membership is OR: two selected rooms
/// mean "in either room". Mirrors todo's `NoteFilter`, including the
/// null-means-unchanged [copyWith] convention.
@immutable
class ItemFilter {
  /// Creates a filter; every facet defaults to unrestricted.
  const ItemFilter({
    this.query = '',
    this.locationIds = const {},
    this.categories = const {},
    this.stock = const {},
    this.flags = const {},
  });

  /// Case-insensitive substring matched against name, notes and category.
  final String query;

  /// Place ids to include; empty means any.
  ///
  /// Matched by **exact id**, so a caller wanting "the hallway and
  /// everything in it" must expand the selection itself with
  /// `ItemRepository.subtreeIds`. Deliberate: resolving a subtree needs the
  /// location records, and a filter that reached for them could no longer
  /// be a value object with a working `==` — which `ItemsScreen` relies on
  /// to tell a new filter from the one it is already showing.
  final Set<String> locationIds;

  /// Categories to include; empty means any.
  final Set<String> categories;

  /// Stock states to include; empty means any.
  final Set<StockState> stock;

  /// Flags an item must have. AND-combined: selecting both means an item must
  /// be wanted *and* sellable.
  final Set<ItemFlag> flags;

  /// Whether this filter restricts nothing.
  bool get isEmpty =>
      query.trim().isEmpty &&
      locationIds.isEmpty &&
      categories.isEmpty &&
      stock.isEmpty &&
      flags.isEmpty;

  /// How many facets are active, for the filter button's badge.
  ///
  /// Counts facets, not selections: picking three rooms is still one active
  /// restriction from the user's point of view.
  int get activeCount {
    var count = 0;
    if (query.trim().isNotEmpty) count++;
    if (locationIds.isNotEmpty) count++;
    if (categories.isNotEmpty) count++;
    if (stock.isNotEmpty) count++;
    if (flags.isNotEmpty) count++;
    return count;
  }

  /// Whether [item] passes every facet.
  ///
  /// Lives on the filter rather than in the repository so the same predicate
  /// backs both the live list and any preset (the shopping screen's two tabs
  /// are just filters).
  bool matches(Item item) {
    if (!_matchesQuery(item)) return false;
    if (locationIds.isNotEmpty && !locationIds.contains(item.locationId)) {
      return false;
    }
    if (categories.isNotEmpty && !_containsFold(categories, item.category)) {
      return false;
    }
    if (stock.isNotEmpty && !stock.contains(item.stockState)) return false;
    if (flags.contains(ItemFlag.wanted) && !item.wanted) return false;
    if (flags.contains(ItemFlag.sellable) && !item.sellable) return false;
    return true;
  }

  bool _matchesQuery(Item item) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return item.name.toLowerCase().contains(needle) ||
        item.notes.toLowerCase().contains(needle) ||
        item.category.toLowerCase().contains(needle);
  }

  // Free-text room/container/category means "Cables" and "cables" can both
  // exist; fold case here so a filter chip picks up both.
  static bool _containsFold(Set<String> haystack, String needle) {
    final folded = needle.toLowerCase();
    return haystack.any((candidate) => candidate.toLowerCase() == folded);
  }

  /// Value equality, so a screen holding a filter can tell a genuinely new
  /// restriction from a rebuild handing it an identical one. Without it the
  /// items tab would re-subscribe its query stream on every parent rebuild.
  @override
  bool operator ==(Object other) =>
      other is ItemFilter &&
      other.query == query &&
      _sameSet(other.locationIds, locationIds) &&
      _sameSet(other.categories, categories) &&
      _sameSet(other.stock, stock) &&
      _sameSet(other.flags, flags);

  @override
  int get hashCode => Object.hash(
    query,
    // Sets are unordered, so their own hashCode is identity-based and would
    // make two equal filters hash differently. Fold instead, commutatively.
    _setHash(locationIds),
    _setHash(categories),
    _setHash(stock),
    _setHash(flags),
  );

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static int _setHash<T>(Set<T> values) =>
      values.fold(0, (acc, value) => acc ^ value.hashCode);

  /// Returns a copy with the given facets replaced; null leaves a facet
  /// unchanged. Pass an empty set to clear one.
  ItemFilter copyWith({
    String? query,
    Set<String>? locationIds,
    Set<String>? categories,
    Set<StockState>? stock,
    Set<ItemFlag>? flags,
  }) => ItemFilter(
    query: query ?? this.query,
    locationIds: locationIds ?? this.locationIds,
    categories: categories ?? this.categories,
    stock: stock ?? this.stock,
    flags: flags ?? this.flags,
  );
}
