import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [field] is in its error state.
///
/// Textgate: validators return `invalidField` (empty, non-null), so tests
/// read the decorator's error state instead of looking for a sentence.
bool hasFieldError(WidgetTester tester, Finder field) {
  final decorator = tester.widget<InputDecorator>(
    find.descendant(of: field, matching: find.byType(InputDecorator)),
  );
  return decorator.decoration.errorText != null;
}
