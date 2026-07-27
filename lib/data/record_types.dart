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

/// Field name carrying an adjustment's timestamp, read by the pruner.
const String kAtField = 'at';

/// How long adjustment history is kept.
///
/// Well past the 90-day rate window, so pruning can never remove a record the
/// projection would have used.
const Duration kAdjustmentHorizon = Duration(days: 180);

/// Whether [record] is an adjustment.
///
/// A missing or unrecognised type reads as an item, which is the safe
/// default: unknown records are then never pruned, so a record kind written
/// by a newer build survives a round-trip through an older one.
bool isAdjustmentRecord(Record record) =>
    record.fields[kTypeField]?.$1 == kTypeAdjustment;

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
