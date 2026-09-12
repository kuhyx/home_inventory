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
  group('QuantityStepper', () {
    testWidgets('renders the quantity and unit', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: QuantityStepper(
            quantity: 2.5,
            unit: 'kg',
            onUse: () {},
            onRestock: () {},
          ),
        ),
      );

      expect(find.text('2.5'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
    });

    testWidgets('hides the unit when blank', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: QuantityStepper(
            quantity: 3,
            unit: '',
            onUse: () {},
            onRestock: () {},
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the two buttons carry different meanings', (tester) async {
      var used = 0;
      var restocked = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: QuantityStepper(
            quantity: 3,
            unit: '',
            onUse: () => used++,
            onRestock: () => restocked++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.tap(find.byIcon(Icons.add));

      expect(used, 1);
      expect(restocked, 1);
    });

    // You cannot use what you do not have; leaving it enabled would write a
    // clamped no-op adjustment.
    testWidgets('cannot use below zero', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: QuantityStepper(
            quantity: 0,
            unit: '',
            onUse: () {},
            onRestock: () {},
          ),
        ),
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
  group('SuggestField', () {
    testWidgets('shows no chip row when there are no suggestions', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpApp(
        tester,
        Scaffold(
          body: SuggestField(controller: controller, label: 'Room'),
        ),
      );

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('tapping a chip fills the field and reports it', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? reported;

      await pumpApp(
        tester,
        Scaffold(
          body: SuggestField(
            controller: controller,
            label: 'Room',
            suggestions: const ['Kitchen', 'Shed'],
            onChanged: (value) => reported = value,
          ),
        ),
      );
      await tester.tap(find.text('Kitchen'));
      await tester.pump();

      expect(controller.text, 'Kitchen');
      expect(reported, 'Kitchen');
    });

    testWidgets('validates through the enclosing form', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final formKey = GlobalKey<FormState>();

      await pumpApp(
        tester,
        Scaffold(
          body: Form(
            key: formKey,
            child: SuggestField(
              controller: controller,
              label: 'Name',
              validator: (value) => (value ?? '').isEmpty ? 'Required' : null,
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
    });
  });
}
