/// How close a dated item is to going off.
library;

/// Tuning for the best-before projection.
abstract final class FreshnessWindow {
  /// How far ahead of the date an item starts warning.
  ///
  /// Five days, which is one shopping trip's worth of lead time: long enough
  /// that the warning is actionable, short enough that the list of things
  /// "due soon" is not just the whole fridge.
  static const int dueSoonDays = 5;
}

/// Where an item sits relative to its own best-before date.
///
/// Deliberately a *derived* value rather than a stored flag, for the same
/// reason `StockState` is: a stored flag is a second source of truth that
/// goes stale the moment the clock moves, and no device would be writing to
/// correct it.
enum FreshnessState {
  /// Dated, and further out than [FreshnessWindow.dueSoonDays].
  fresh,

  /// Dated, and within [FreshnessWindow.dueSoonDays] of the date.
  dueSoon,

  /// The date has passed.
  expired,
}

/// One item's distance from its best-before date.
class Freshness {
  /// Creates a freshness reading.
  const Freshness({required this.state, required this.daysLeft});

  /// Reads [bestBefore] as of [now].
  factory Freshness.between(DateTime now, DateTime bestBefore) {
    final days = _wholeDaysBetween(now, bestBefore);
    return Freshness(
      state: switch (days) {
        < 0 => FreshnessState.expired,
        <= FreshnessWindow.dueSoonDays => FreshnessState.dueSoon,
        _ => FreshnessState.fresh,
      },
      daysLeft: days,
    );
  }

  /// Whole days from today to the date; negative once it has passed.
  ///
  /// Counted in **whole calendar days**, not elapsed hours. "Best before
  /// tomorrow" has to read as 1 whether it is now breakfast or midnight, and
  /// an hours-based difference would round it to 0 for most of the day.
  final int daysLeft;

  /// Whether the item is fine, due soon, or past its date.
  final FreshnessState state;

  /// One-line rendering for a badge.
  String get label => switch (daysLeft) {
    < 0 => 'Expired',
    0 => 'Today',
    _ => '${daysLeft}d left',
  };

  /// Whole calendar days between two instants.
  ///
  /// Both sides are collapsed to their own date parts before subtracting, so
  /// the answer never depends on the time of day and never loses or gains a
  /// day to a daylight-saving shift — subtracting the raw instants would do
  /// both.
  static int _wholeDaysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  @override
  String toString() => 'Freshness($label, ${state.name})';
}
