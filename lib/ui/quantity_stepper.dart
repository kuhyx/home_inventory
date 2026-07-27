/// The −/+ control that drives every casual quantity change.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/theme.dart';

/// A large quantity readout flanked by decrement and increment buttons.
///
/// The two buttons carry different *meanings*, not just different signs:
/// decrement means "I used some" and increment means "I bought some". The
/// caller maps them to the matching `AdjustmentSource`, which is what keeps
/// the consumption rate honest.
class QuantityStepper extends StatelessWidget {
  /// Creates a stepper.
  const QuantityStepper({
    required this.quantity,
    required this.unit,
    required this.onUse,
    required this.onRestock,
    super.key,
  });

  /// Current amount on hand.
  final double quantity;

  /// Unit label, empty for a plain count.
  final String unit;

  /// Called when the user takes one away.
  final VoidCallback onUse;

  /// Called when the user adds one.
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: quantity <= 0 ? null : onUse,
          icon: const Icon(Icons.remove),
          tooltip: 'Used one',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              Text(
                formatQuantity(quantity),
                style: TextStyle(
                  fontSize: AppTextSize.display,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onRestock,
          icon: const Icon(Icons.add),
          tooltip: 'Added one',
        ),
      ],
    );
  }
}
