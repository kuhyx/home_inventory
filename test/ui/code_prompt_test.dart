import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/ui/code_prompt.dart';

import '../support/pump.dart';

void main() {
  Future<List<CodeEntry?>> open(
    WidgetTester tester, {
    bool withAmount = false,
  }) async {
    final results = <CodeEntry?>[];
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => results.add(
              await promptForCode(
                context,
                title: 'Scan',
                withAmount: withAmount,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('returns the typed code', (tester) async {
    final results = await open(tester);

    await tester.enterText(find.byType(TextField), '590');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(results.single!.code, '590');
    expect(results.single!.amount, 1);
  });

  testWidgets('hides the amount field unless it is asked for', (tester) async {
    await open(tester);

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('returns the typed amount alongside the code', (tester) async {
    final results = await open(tester, withAmount: true);

    await tester.enterText(find.byType(TextField).first, '590');
    await tester.enterText(find.byType(TextField).last, '500');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(results.single!.amount, 500);
  });

  // Refusing to close over a typo in a field most people never touch would be
  // worse than the sane default; linkBarcode rejects a bad amount anyway.
  testWidgets('an unparseable amount falls back to one', (tester) async {
    final results = await open(tester, withAmount: true);

    await tester.enterText(find.byType(TextField).first, '590');
    await tester.enterText(find.byType(TextField).last, 'lots');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(results.single!.amount, 1);
  });

  testWidgets('submitting from the keyboard works too', (tester) async {
    final results = await open(tester);

    await tester.enterText(find.byType(TextField), '590');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results.single!.code, '590');
  });

  testWidgets('a blank code comes back as nothing', (tester) async {
    final results = await open(tester);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });

  testWidgets('cancelling comes back as nothing', (tester) async {
    final results = await open(tester);

    await tester.enterText(find.byType(TextField), '590');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });
}
