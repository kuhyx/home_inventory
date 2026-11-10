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

      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('shows the low glyph in the warning colour', (tester) async {
      await pumpApp(tester, const StockBadge(state: StockState.low));

      final icon = tester.widget<Icon>(find.byIcon(Icons.battery_2_bar));
      expect(icon.color, AppStatusColors.dark.warning);
      expect(find.bySemanticsLabel('Low'), findsOneWidget);
    });

    testWidgets('shows the out glyph in the error colour', (tester) async {
      await pumpApp(tester, const StockBadge(state: StockState.out));

      final icon = tester.widget<Icon>(find.byIcon(Icons.battery_0_bar));
      expect(icon.color, buildDarkTheme().colorScheme.error);
      expect(find.bySemanticsLabel('Out'), findsOneWidget);
    });
  });
}
