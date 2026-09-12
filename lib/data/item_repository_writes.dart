/// Every write the app makes to an item, and the adjustment it records.
part of 'item_repository.dart';

/// Creating, updating and deleting items, quantity changes included.
extension ItemWrites on ItemRepository {
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
    return await _writeQuantity(current, next, source, at);
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
    return await _writeQuantity(current, next, source, now ?? DateTime.now());
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
      Record(id: id, fields: {...?existing?.fields, ...changed}),
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
}
