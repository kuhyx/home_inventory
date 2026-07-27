/// A text field with tap-to-fill suggestions drawn from existing data.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// A labelled text field with a scrollable row of suggestion chips beneath it.
///
/// Chips rather than a dropdown overlay: on a phone, filling a room name is
/// one tap on a value you already use, and an overlay both fights the
/// keyboard and is markedly harder to drive reliably. The parent supplies
/// suggestions already ranked by usage, so the common answer is leftmost.
///
/// This is what makes free-text rooms, containers and categories workable
/// instead of a typo farm — the user picks an existing string far more often
/// than they type a new one.
class SuggestField extends StatelessWidget {
  /// Creates a suggest field.
  const SuggestField({
    required this.controller,
    required this.label,
    this.suggestions = const [],
    this.keyboardType,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.onChanged,
    super.key,
  });

  /// Controller owned by the parent form.
  final TextEditingController controller;

  /// Field label.
  final String label;

  /// Values to offer, most useful first. Empty hides the chip row entirely.
  final List<String> suggestions;

  /// Keyboard type, e.g. numeric for a quantity.
  final TextInputType? keyboardType;

  /// Whether to take focus on mount.
  final bool autofocus;

  /// Capitalisation behaviour for the soft keyboard.
  final TextCapitalization textCapitalization;

  /// Optional form validation.
  final String? Function(String?)? validator;

  /// Called after the text changes, including from a chip tap.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          keyboardType: keyboardType,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          validator: validator,
          onChanged: onChanged,
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final value = suggestions[index];
                  return ActionChip(
                    label: Text(value),
                    onPressed: () {
                      controller.text = value;
                      onChanged?.call(value);
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
