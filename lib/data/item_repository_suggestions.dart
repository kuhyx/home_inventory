/// What the free-text fields offer, drawn from what is already in use.
part of 'item_repository.dart';

/// Ranked values for the form fields that are still free text.
///
/// Ordering by usage is what makes them workable: the category you file
/// things under most is the first suggestion, so the common case is a tap
/// rather than typing — which is also what keeps casing consistent.
extension ValueSuggestions on ItemRepository {
  // Rooms and containers had ranked-value sources here too, feeding the
  // free-text fields on the two item forms. Those fields are gone: places are
  // records now, picked from the tree, so ranking the legacy strings would
  // only offer values nothing writes any more.

  /// Categories already in use, most-used first.
  List<String> knownCategories() => _rankedValues((item) => item.category);

  /// Units already in use, most-used first.
  List<String> knownUnits() => _rankedValues((item) => item.unit);

  List<String> _rankedValues(String Function(Item) select) {
    final counts = <String, int>{};
    for (final item in _liveItems()) {
      final value = select(item);
      if (value.isEmpty) continue;
      counts.update(value, (n) => n + 1, ifAbsent: () => 1);
    }
    final values = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return values;
  }
}
