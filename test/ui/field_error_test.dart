import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/ui/best_before_field.dart';
import 'package:home_inventory/ui/field_error.dart';
import 'package:home_inventory/ui/number_input.dart';

void main() {
  // Textgate: a bad field must still fail validation (non-null) while
  // painting nothing (empty).
  test('invalidField fails a form but paints no words', () {
    expect(invalidField, isNotNull);
    expect(invalidField, isEmpty);
  });

  test('every validator reports a bad value as invalidField', () {
    expect(validateNumberInput('', required: true), invalidField);
    expect(validateNumberInput('lots', required: false), invalidField);
    expect(validateNumberInput('-1', required: false), invalidField);
    expect(validateIsoDate('02/08/2026'), invalidField);
    expect(validateIsoDate('2026-13-45'), invalidField);
  });

  test('a good or optional-blank value passes', () {
    expect(validateNumberInput('', required: false), isNull);
    expect(validateNumberInput('2,5', required: true), isNull);
    expect(validateIsoDate('2026-08-02'), isNull);
  });
}
