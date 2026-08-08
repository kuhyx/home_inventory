import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26, 9, 30);

  group('Freshness.between', () {
    test('a date past today is expired', () {
      final freshness = Freshness.between(now, DateTime.utc(2026, 7, 25));

      expect(freshness.state, FreshnessState.expired);
      expect(freshness.daysLeft, -1);
    });

    test('today itself is due soon, not expired', () {
      final freshness = Freshness.between(now, DateTime.utc(2026, 7, 26));

      expect(freshness.state, FreshnessState.dueSoon);
      expect(freshness.daysLeft, 0);
    });

    test('the last day of the window is still due soon', () {
      final freshness = Freshness.between(
        now,
        DateTime.utc(2026, 7, 26 + FreshnessWindow.dueSoonDays),
      );

      expect(freshness.state, FreshnessState.dueSoon);
      expect(freshness.daysLeft, FreshnessWindow.dueSoonDays);
    });

    test('one day past the window is fresh', () {
      final freshness = Freshness.between(
        now,
        DateTime.utc(2026, 7, 27 + FreshnessWindow.dueSoonDays),
      );

      expect(freshness.state, FreshnessState.fresh);
    });

    // The whole point of collapsing both sides to their date parts: an
    // hours-based difference would call this 0 days for most of the day, and
    // "best before tomorrow" would read as "today" until midnight.
    test('counts whole calendar days, not elapsed hours', () {
      final lateEvening = DateTime.utc(2026, 7, 26, 23, 59);
      final earlyMorning = DateTime.utc(2026, 7, 27, 0, 1);

      expect(Freshness.between(lateEvening, earlyMorning).daysLeft, 1);
    });
  });

  group('label', () {
    test('past dates say Expired rather than a negative count', () {
      final label = Freshness.between(now, DateTime.utc(2026, 7, 1)).label;

      expect(label, 'Expired');
      expect(label, isNot(contains('-')));
    });

    test('the date itself says Today', () {
      expect(
        Freshness.between(now, DateTime.utc(2026, 7, 26)).label,
        'Today',
      );
    });

    test('future dates count the days', () {
      expect(
        Freshness.between(now, DateTime.utc(2026, 7, 29)).label,
        '3d left',
      );
    });
  });

  test('toString carries the label and the state', () {
    final text = Freshness.between(now, DateTime.utc(2026, 7, 29)).toString();

    expect(text, contains('3d left'));
    expect(text, contains('dueSoon'));
  });
}
