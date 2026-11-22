// Tooltip guard: an icon's hover word is the one we wrote, never a Flutter
// default, and every literal tooltip is one word (letters or hyphen, ≤ 20).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/screens/items_screen.dart';
import 'package:home_inventory/screens/locations_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump.dart';

final _oneWord = RegExp(r'^[A-Za-z][A-Za-z-]{0,19}$');

/// Hovers the widget under [key] with a mouse and returns the tooltip text
/// that ends up painted.
Future<List<String>> _hoverWords(WidgetTester tester, Key key) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.byKey(key)));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return [
    for (final t in tester.widgetList<Tooltip>(
      find.ancestor(of: find.byKey(key), matching: find.byType(Tooltip)),
    ))
      t.message ?? '',
    for (final t in tester.widgetList<Tooltip>(
      find.descendant(of: find.byKey(key), matching: find.byType(Tooltip)),
    ))
      t.message ?? '',
  ];
}

void main() {
  final at = DateTime.utc(2026, 7, 26);
  late ItemRepository repo;

  setUp(() async => repo = await ItemRepository.openInMemory());
  tearDown(() async => repo.close());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, screen);
    await tester.pumpAndSettle();
  }

  testWidgets('sort popup shows Sort, not the default', (tester) async {
    await pump(tester, ItemsScreen(repository: repo, now: () => at));
    final words = await _hoverWords(tester, const Key('items_header_sort'));
    expect(words, ['Sort']);
    expect(find.text('Show menu'), findsNothing);
    expect(find.text('Sort'), findsOneWidget);
  });

  testWidgets('place menu shows Menu, not the default', (tester) async {
    await repo.createLocation(name: 'Kitchen', now: at);
    await pump(
      tester,
      LocationsScreen(repository: repo, onSelect: (_) {}, now: () => at),
    );
    final words = await _hoverWords(tester, const Key('menu_more'));
    expect(words, ['Menu']);
    expect(find.text('Show menu'), findsNothing);
    expect(find.text('Menu'), findsOneWidget);
  });

  test('every literal tooltip in lib is one word', () {
    // Each `message:` / `tooltip:` line, with every quoted literal on it
    // (covers `expanded ? 'Collapse' : 'Expand'`).
    final key = RegExp(r'\b(?:message|tooltip):');
    final quoted = RegExp("'([^']*)'");
    final bad = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync().where(key.hasMatch)) {
        for (final m in quoted.allMatches(line)) {
          if (!_oneWord.hasMatch(m.group(1)!)) {
            bad.add('${file.path}: ${m.group(1)}');
          }
        }
      }
    }
    expect(bad, isEmpty);
  });
}
