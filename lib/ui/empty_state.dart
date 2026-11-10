/// The placeholder shown when a list has nothing in it.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// A centred glyph with a small corner badge for an empty list.
///
/// Textgate: no painted words. The glyph names the list, the [badge] says
/// why it is empty (an add cross for "add the first one", a struck lens for
/// "no matches"), and [semanticLabel] carries the old sentence for screen
/// readers only.
class EmptyState extends StatelessWidget {
  /// Creates an empty-state placeholder.
  const EmptyState({
    required this.icon,
    required this.badge,
    required this.semanticLabel,
    super.key,
  });

  /// Glyph for the list itself.
  final IconData icon;

  /// Corner glyph saying why the list is empty.
  final IconData badge;

  /// Spoken-only description, never painted.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: 72,
          child: Stack(
            children: [
              Icon(icon, size: 64, color: colors.onSurfaceVariant),
              Positioned(
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Icon(badge, size: 20, color: colors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
