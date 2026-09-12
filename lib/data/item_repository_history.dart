/// The immutable adjustment log, and the consumption-rate projection read
/// off it.
part of 'item_repository.dart';

/// Reading an item's adjustment history and projecting from it.
extension AdjustmentHistory on ItemRepository {
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
}
