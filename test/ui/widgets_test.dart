import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/empty_state.dart';
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
}
