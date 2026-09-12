/// Reading and checking the numbers a form asks for.
library;

/// Parses [text] as a quantity, or null when it is not a number.
///
/// A comma is accepted as the decimal separator: the Polish keyboard offers
/// one, `double.tryParse` rejects it, and "2,5" typed into a quantity is not
/// a mistake the user should have to notice.
double? parseNumberInput(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Rejects a blank [value] when [required], and anything unusable always.
String? validateNumberInput(String? value, {required bool required}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? 'Enter a number' : null;
  final parsed = parseNumberInput(text);
  if (parsed == null) return 'Not a number';
  if (parsed < 0) return 'Cannot be negative';
  return null;
}
