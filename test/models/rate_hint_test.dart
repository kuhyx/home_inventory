import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/rate_hint.dart';

void main() {
  group('label', () {
    test('reads as whole days when at least one remains', () {
      const hint = RateHint(perDay: 0.5, daysLeft: 9, sampleCount: 4);

      expect(hint.label, '~9 days left');
    });

    // Never render "~0 days left" — it reads as a bug rather than urgency.
    test('degrades gracefully below a day', () {
      const hint = RateHint(perDay: 4, daysLeft: 0, sampleCount: 5);

      expect(hint.label, 'less than a day left');
    });
  });

  test('toString carries the label and the sample count', () {
    const hint = RateHint(perDay: 0.5, daysLeft: 9, sampleCount: 4);

    expect(hint.toString(), contains('~9 days left'));
    expect(hint.toString(), contains('4'));
  });

  // The projection must never outlive the retention horizon, or pruning
  // could delete a record the rate still needed.
  test('the retention horizon is wider than the rate window', () {
    expect(RateWindow.window.inDays, lessThan(180));
    expect(RateWindow.minSamples, greaterThan(1));
    expect(RateWindow.minSpanDays, greaterThan(0));
    expect(RateWindow.maxDaysLeft, greaterThan(0));
  });
}
