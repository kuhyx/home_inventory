/// Headline counts for the list screen's summary strip.
library;

/// Aggregate counts across the whole inventory.
class InventorySummary {
  /// Creates a summary.
  const InventorySummary({
    required this.total,
    required this.low,
    required this.out,
    required this.wanted,
    required this.sellable,
    required this.toBuy,
  });

  /// An inventory with nothing in it.
  static const empty = InventorySummary(
    total: 0,
    low: 0,
    out: 0,
    wanted: 0,
    sellable: 0,
    toBuy: 0,
  );

  /// Every live (non-deleted) item.
  final int total;

  /// Items at or below their threshold but not yet at zero.
  final int low;

  /// Items at zero.
  final int out;

  /// Items flagged as wanted.
  final int wanted;

  /// Items flagged as sellable.
  final int sellable;

  /// How many items belong on the shopping list: everything not fully
  /// stocked, plus anything wanted.
  ///
  /// Counted over the items themselves, not derived by adding [low], [out]
  /// and [wanted] — an item can be both out *and* wanted, and would be
  /// double-counted.
  final int toBuy;
}
