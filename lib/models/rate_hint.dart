/// The informational "you'll run out in about N days" projection.
library;

/// Tuning constants for the consumption-rate projection.
///
/// These are deliberately conservative. The deterministic warner is
/// `Item.lowStockAt`; the hint exists only to add lead time, so when in doubt
/// it must stay quiet rather than guess.
abstract final class RateWindow {
  /// How far back usage is counted.
  static const Duration window = Duration(days: 90);

  /// Fewest in-window `use` adjustments before a projection is offered.
  static const int minSamples = 3;

  /// Shortest observation span, in days. Three uses in one afternoon says
  /// nothing about a weekly rate.
  static const double minSpanDays = 14;

  /// Longest projection worth showing. "~3 years left" is noise.
  static const int maxDaysLeft = 365;
}

/// A consumption projection for one item.
class RateHint {
  /// Creates a projection.
  const RateHint({
    required this.perDay,
    required this.daysLeft,
    required this.sampleCount,
  });

  /// Average amount consumed per day over the window.
  final double perDay;

  /// Whole days until the item reaches its low-stock threshold — not until
  /// zero. "Buy more in ~9 days" is actionable; "you'll have literally none
  /// in ~9 days" is not.
  final int daysLeft;

  /// How many usage records backed this estimate, for an explanatory
  /// tooltip.
  final int sampleCount;

  /// One-line rendering. Never exposes the raw [perDay] — a spurious
  /// precision the estimate does not have.
  String get label =>
      daysLeft >= 1 ? '~$daysLeft days left' : 'less than a day left';

  @override
  String toString() => 'RateHint($label, from $sampleCount uses)';
}
