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
  group('StockBadge', () {
    // A badge on every row would drown out the rows that matter.
    testWidgets('draws nothing when stock is fine', (tester) async {
      await pumpApp(tester, const StockBadge(state: StockState.ok));

      expect(find.text('Low'), findsNothing);
      expect(find.text('Out'), findsNothing);
    });

    testWidgets('shows Low in the warning colour', (tester) async {
      await pumpApp(tester, const StockBadge(state: StockState.low));

      expect(find.text('Low'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Low'));
      expect(text.style?.color, AppStatusColors.dark.warning);
    });

    testWidgets('shows Out in the error colour', (tester) async {
      await pumpApp(tester, const StockBadge(state: StockState.out));

      expect(find.text('Out'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Out'));
      expect(text.style?.color, buildDarkTheme().colorScheme.error);
    });
  });
}
