/// How the one shared CRDT log holds two kinds of record, and how it stays
/// bounded without breaking convergence.
library;

import 'package:crdt_sync/crdt_sync.dart';

/// Field name carrying a record's kind.
///
/// A field rather than an id prefix: the record id stays an opaque CRDT key,
/// the kind is correctable, and a third kind later is an equality check
/// instead of string parsing.
const String kTypeField = 'type';

/// [kTypeField] value for an [Item] record.
const String kTypeItem = 'item';

/// [kTypeField] value for an `Adjustment` record.
const String kTypeAdjustment = 'adjustment';

/// [kTypeField] value for a `Location` record.
const String kTypeLocation = 'location';

/// [kTypeField] value for an `ItemType` record.
const String kTypeItemType = 'item_type';

/// Field name carrying an adjustment's timestamp, read by the pruner.
const String kAtField = 'at';

/// How long adjustment history is kept.
///
/// Well past the 90-day rate window, so pruning can never remove a record the
/// projection would have used.
const Duration kAdjustmentHorizon = Duration(days: 180);

/// Whether [record] is an adjustment.
///
/// An unrecognised type is not an adjustment, which is the safe default *for
/// pruning*: unknown records are then never dropped, so a record kind written
/// by a newer build survives a round-trip through an older one. Note this is
/// deliberately not the inverse of [isItemRecord] — see there for why the two
/// predicates answer different questions.
bool isAdjustmentRecord(Record record) =>
    record.fields[kTypeField]?.$1 == kTypeAdjustment;

/// Whether [record] should be read as an item.
///
/// An **allowlist**, not the negation of [isAdjustmentRecord], and the
/// difference is the whole point. A blocklist answers "everything that is not
/// an adjustment is an item", which was true when those were the only two
/// kinds and becomes actively harmful the moment a newer build writes a third:
/// an older build would render every location as a phantom item with quantity
/// zero. Retention wants the opposite default — keep what you do not
/// understand — so the two predicates stay separate on purpose.
///
/// A *missing* type still reads as an item, for records written before
/// [kTypeField] existed.
bool isItemRecord(Record record) {
  final type = record.fields[kTypeField]?.$1;
  return type == null || type == kTypeItem;
}

/// Drops adjustment records older than [kAdjustmentHorizon].
///
/// This is a **pure function of each record's own immutable content** plus
/// [now], which is what makes it converge: two devices can only disagree
/// about records sitting within their clock skew of the boundary — hours,
/// against a horizon of months — and that disagreement heals by itself as
/// time advances past the boundary on both. Since adjustments are never
/// edited, presence is the only observable, and it decreases monotonically.
///
/// Two rules that look like details and are not:
///
/// * **Items are never dropped, tombstoned or not.** Dropping an item
///   tombstone resurrects a deleted item on a device that has been offline
///   long enough — user-visible harm. An ancient adjustment briefly
///   reappearing is invisible: it is outside the rate window by construction.
/// * **This must also run inside the `decode` hook of `syncLog`,** not only
///   on load. `syncLog` pushes the merge of the local log with every peer
///   file, so pruning locally alone means a peer's stale file re-introduces
///   the record and it gets pushed straight back — a commit on every sync,
///   forever, with the log never shrinking.
Log dropAncientAdjustments(Log log, DateTime now) => {
  for (final entry in log.entries)
    if (!_isAncient(entry.value, now)) entry.key: entry.value,
};

bool _isAncient(Record record, DateTime now) {
  if (!isAdjustmentRecord(record)) return false;
  final raw = record.fields[kAtField]?.$1;
  if (raw is! String) return false;
  final at = DateTime.tryParse(raw);
  // An unparseable timestamp is kept: it is a record we do not understand,
  // and silently deleting those is how data goes missing.
  if (at == null) return false;
  return now.difference(at) > kAdjustmentHorizon;
}
