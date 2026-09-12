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
  group('ItemTile', () {
    testWidgets('shows name, quantity and location', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: ItemTile(
            item: itemFixture(
              name: 'USB-C cable',
              quantity: 4,
              room: 'Office',
              container: 'Drawer',
            ),
          ),
        ),
      );

      expect(find.text('USB-C cable'), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
      expect(find.textContaining('Office › Drawer'), findsOneWidget);
    });

    testWidgets('includes the unit when there is one', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: ItemTile(item: itemFixture(quantity: 2.5, unit: 'kg')),
        ),
      );

      expect(find.textContaining('2.5 kg'), findsOneWidget);
    });

    testWidgets('omits the separator when there is no location', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Scaffold(body: ItemTile(item: itemFixture(quantity: 3))),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('reports taps', (tester) async {
      var tapped = false;
      await pumpApp(
        tester,
        Scaffold(
          body: ItemTile(
            item: itemFixture(name: 'Tap me'),
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));

      expect(tapped, isTrue);
    });
  });
}
