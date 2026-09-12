import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/freshness.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/empty_state.dart';
import 'package:home_inventory/ui/freshness_badge.dart';
import 'package:home_inventory/ui/item_tile.dart';
import 'package:home_inventory/ui/quantity_stepper.dart';
import 'package:home_inventory/ui/stock_badge.dart';
import 'package:home_inventory/ui/suggest_field.dart';
import 'package:home_inventory/ui/theme.dart';

import '../support/builders.dart';
import '../support/pump.dart';

void main() {
  testWidgets('EmptyState shows its icon, title and message', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Nothing here yet',
          message: 'Tap + to add something.',
        ),
      ),
    );

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Tap + to add something.'), findsOneWidget);
  });
  group('FreshnessBadge', () {
    final now = DateTime.utc(2026, 7, 26);

    testWidgets('draws nothing while the date is far off', (tester) async {
      await pumpApp(
        tester,
        FreshnessBadge(freshness: Freshness.between(now, DateTime.utc(2027))),
      );

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows the countdown in the warning colour', (tester) async {
      await pumpApp(
        tester,
        FreshnessBadge(
          freshness: Freshness.between(now, DateTime.utc(2026, 7, 28)),
        ),
      );

      final text = tester.widget<Text>(find.text('2d left'));
      expect(text.style?.color, AppStatusColors.dark.warning);
    });

    testWidgets('shows Expired in the error colour', (tester) async {
      await pumpApp(
        tester,
        FreshnessBadge(
          freshness: Freshness.between(now, DateTime.utc(2026, 7, 1)),
        ),
      );

      final text = tester.widget<Text>(find.text('Expired'));
      expect(text.style?.color, buildDarkTheme().colorScheme.error);
    });
  });
  group('ItemTile and dates', () {
    testWidgets('badges an item that is close to its date', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: ItemTile(
            item: itemFixture(
              name: 'Milk',
              bestBefore: DateTime.utc(2026, 7, 28),
            ),
            asOf: DateTime.utc(2026, 7, 26),
          ),
        ),
      );

      expect(find.text('2d left'), findsOneWidget);
    });

    // The default clock path: a date this far out is fresh whenever the suite
    // runs, so the row stays quiet.
    testWidgets('falls back to now when no clock is given', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: ItemTile(item: itemFixture(bestBefore: DateTime(2999))),
        ),
      );

      expect(find.byType(FreshnessBadge), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
    });

    testWidgets('an undated item gets no badge at all', (tester) async {
      await pumpApp(tester, Scaffold(body: ItemTile(item: itemFixture())));

      expect(find.byType(FreshnessBadge), findsNothing);
    });
  });
}
