/// The best-before field: one date shape, typed or picked.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/suggest_field.dart';

/// The one date shape the field accepts, and the one it writes back.
///
/// ISO order rather than anything local: it sorts as text, it is
/// unambiguous between the Polish and English readings of `03/04`, and it
/// is what the CRDT record already stores.
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// [date] in the one shape the field reads and writes; empty for null.
String formatIsoDate(DateTime? date) => date == null
    ? ''
    : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

/// Parses [text], or null for blank **and** for anything malformed.
///
/// The round-trip check is the whole point. `DateTime.parse` does not reject
/// an impossible date — it rolls it over, quietly turning `2026-13-45` into
/// 2027-02-14 — so parsing alone would store a date the user never typed and
/// then show it back to them as if they had.
DateTime? parseIsoDate(String text) {
  final trimmed = text.trim();
  if (!_isoDate.hasMatch(trimmed)) return null;
  final parsed = DateTime.tryParse(trimmed);
  return parsed != null && formatIsoDate(parsed) == trimmed ? parsed : null;
}

/// Rejects a date that is the wrong shape, or that no calendar has.
String? validateIsoDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  if (!_isoDate.hasMatch(text)) return 'Use YYYY-MM-DD';
  if (parseIsoDate(text) == null) return 'Not a real date';
  return null;
}

/// A typed ISO date with a calendar button beside it.
///
/// Both, not either: the picker is faster for "next Tuesday" and unbearable
/// for "March 2028". The text field stays the one source of truth, so the
/// calendar writes into it rather than into a second piece of state.
class BestBeforeField extends StatelessWidget {
  /// Creates the field.
  const BestBeforeField({
    required this.controller,
    required this.now,
    super.key,
  });

  /// Controller owned by the parent form.
  final TextEditingController controller;

  /// Clock the calendar anchors on, so tests are deterministic.
  final DateTime Function() now;

  Future<void> _pick(BuildContext context) async {
    final current = parseIsoDate(controller.text);
    final anchor = now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? anchor,
      firstDate: DateTime(anchor.year - 5),
      lastDate: DateTime(anchor.year + 20),
    );
    if (picked == null) return;
    controller.text = formatIsoDate(picked);
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: SuggestField(
          controller: controller,
          label: 'Best before (YYYY-MM-DD, blank for never)',
          keyboardType: TextInputType.datetime,
          textCapitalization: TextCapitalization.none,
          validator: validateIsoDate,
        ),
      ),
      IconButton(
        onPressed: () => _pick(context),
        icon: const Icon(Icons.calendar_today_outlined),
        tooltip: 'Pick a date',
      ),
    ],
  );
}
