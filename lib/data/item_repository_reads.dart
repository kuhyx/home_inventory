/// Querying the inventory: lists, one item, and the headline counts.
part of 'item_repository.dart';

/// The read side of the repository.
extension ItemQueries on ItemRepository {
  /// Every live item, filtered and sorted.
  List<Item> listItems({
    ItemSort sort = ItemSort.updatedDesc,
    ItemFilter filter = const ItemFilter(),
    DateTime? asOf,
  }) {
    final items =
        _liveItems().where((item) => filter.matches(item, asOf: asOf)).toList()
          ..sort(ItemRepository._comparatorFor(sort));
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
        ..sort(ItemRepository._comparatorFor(sort));

  /// [listToBuy] as a stream that re-emits on every write.
  Stream<List<Item>> watchToBuy({ItemSort sort = ItemSort.lowStockFirst}) =>
      _watch(() => listToBuy(sort: sort));
}
