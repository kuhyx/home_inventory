/// The tinted pill both item badges draw.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// A tinted pill holding a glyph and an optional short number.
///
/// Textgate: the glyph shape and the [color] are the two channels; [value]
/// is a number (days left), never a word. [semanticLabel] is spoken only.
class StatusPill extends StatelessWidget {
  /// Creates a pill.
  const StatusPill({
    required this.icon,
    required this.color,
    required this.semanticLabel,
    this.value,
    super.key,
  });

  /// Glyph naming the state.
  final IconData icon;

  /// Status colour for glyph, border and fill.
  final Color color;

  /// Spoken-only description.
  final String semanticLabel;

  /// Optional short number beside the glyph.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color);
    final shown = value;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          // 15% fill and a 40% border, per the shared component spec: a solid
          // status fill would shout louder than the item's own name.
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            if (shown != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(shown, style: style),
            ],
          ],
        ),
      ),
    );
  }
}
