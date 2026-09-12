/// Linking scanned codes to items, applying a scan, and the two list views
/// that hang off the same reading path (expiring soon, and sellable).
part of 'item_repository.dart';

/// Barcode links, scanning, and the expiry/sellable list views.
extension BarcodeQueries on ItemRepository {
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
    return await adjustQuantity(link.itemId, delta, source, now: now);
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
      ..sort(ItemRepository._comparatorFor(ItemSort.expiringFirst));
  }

  /// [listExpiring] as a stream that re-emits on every write.
  Stream<List<Item>> watchExpiring({DateTime? now}) =>
      _watch(() => listExpiring(now: now));

  /// Everything flagged as sellable.
  List<Item> listSellable({ItemSort sort = ItemSort.nameAsc}) =>
      (_liveItems().where((item) => item.sellable).toList())
        ..sort(ItemRepository._comparatorFor(sort));

  /// [listSellable] as a stream that re-emits on every write.
  Stream<List<Item>> watchSellable({ItemSort sort = ItemSort.nameAsc}) =>
      _watch(() => listSellable(sort: sort));
}
