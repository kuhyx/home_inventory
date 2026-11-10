import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two or more letters in a row: a word, as opposed to a number, a unit
/// symbol like `g` or an icon-font glyph (those sit in the private-use area).
final _word = RegExp('[A-Za-z]{2,}');

/// Every painted string on screen that holds a word, minus [content].
///
/// Walks `RichText`, because `Text`, input hints, errors and chip labels all
/// end up as one. Each painted string is matched whole and then word by word
/// against [content], so user data such as an item name may sit inside a
/// longer painted string ("Flour · Kitchen") without tripping the check.
List<String> paintedWords(
  WidgetTester tester, {
  Set<String> content = const {},
}) {
  final found = <String>[];
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = widget.text.toPlainText();
    if (content.contains(text)) continue;
    var rest = text;
    for (final allowed in content) {
      rest = rest.replaceAll(allowed, ' ');
    }
    if (_word.hasMatch(rest)) found.add(text);
  }
  return found;
}

/// Fails with the list of offending strings when any word is painted.
void expectNoWords(WidgetTester tester, {Set<String> content = const {}}) {
  expect(paintedWords(tester, content: content), isEmpty);
}
