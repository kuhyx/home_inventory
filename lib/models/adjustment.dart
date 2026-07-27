/// The append-only history that makes a consumption-rate hint possible.
library;

/// Why a quantity changed.
///
/// This is not decoration — it is the whole reason the rate hint is
/// trustworthy. Without it, recounting a shelf (the app said 10, there are
/// really 6) is indistinguishable from four days of use, and the estimated
/// burn rate roughly quadruples. Only [use] feeds the rate.
///
/// The source is decided by *which affordance the user touched*, never
/// inferred from the sign of the delta.
enum AdjustmentSource {
  /// The user consumed some: the `−` stepper on the detail screen.
  use('use'),

  /// The user bought/refilled some: the `+` stepper, or "Bought".
  restock('restock'),

  /// The user recounted and typed a new number into the form. Excluded from
  /// the rate on purpose.
  correction('correct'),

  /// The quantity an item was created with.
  initial('initial');

  const AdjustmentSource(this.wire);

  /// Stable on-the-wire string. Distinct from the Dart name so renaming the
  /// enum member never rewrites already-synced history.
  final String wire;

  /// Parses [wire], falling back to [correction] for anything unrecognised.
  ///
  /// Falling back rather than throwing keeps a record written by a newer
  /// build readable by an older one; [correction] is the safe default because
  /// it is the source that is *excluded* from the rate.
  static AdjustmentSource fromWire(String? wire) => values.firstWhere(
    (source) => source.wire == wire,
    orElse: () => correction,
  );
}

/// One immutable quantity change.
///
/// Never edited after creation, which is what makes merging trivially
/// correct: ids are uuids so they never collide, and if the same id does
/// appear on two devices the field values are byte-identical, so last-writer
/// -wins returns the same answer whichever clock happens to be greater.
class Adjustment {
  /// Creates an adjustment record.
  const Adjustment({
    required this.id,
    required this.itemId,
    required this.delta,
    required this.at,
    required this.source,
  });

  /// Stable identifier (a uuid v4), also the CRDT record id.
  final String id;

  /// The [Item] this change applies to.
  final String itemId;

  /// Signed change in quantity; negative means the amount went down.
  final double delta;

  /// Device wall-clock time of the change. Used for the rate window, so a
  /// future-dated value (a misconfigured clock) is filtered out rather than
  /// trusted.
  final DateTime at;

  /// Which affordance produced this change.
  final AdjustmentSource source;

  /// How much was consumed, as a positive number; zero for non-decreases.
  double get consumed => delta < 0 ? -delta : 0;

  @override
  String toString() =>
      'Adjustment(item: $itemId, delta: $delta, '
      'source: ${source.wire}, at: $at)';
}
