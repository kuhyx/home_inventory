/// The low/out indicator shown next to an item.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/theme.dart';

/// A small pill naming an item's [StockState], or nothing at all when the
/// item is fine.
///
/// Drawing nothing for [StockState.ok] is deliberate: a badge on every row
/// would make the ones that matter invisible, which is the opposite of what a
/// warning is for.
class StockBadge extends StatelessWidget {
  /// Creates a badge for [state].
  const StockBadge({required this.state, super.key});

  /// The state to render.
  final StockState state;

  @override
  Widget build(BuildContext context) {
    if (state == StockState.ok) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = theme.extension<AppStatusColors>()!;
    // A two-way choice rather than an exhaustive switch: `ok` already
    // returned above, so a third arm would be permanently dead code that the
    // coverage gate could never satisfy honestly.
    final isOut = state == StockState.out;
    final label = isOut ? 'Out' : 'Low';
    final color = isOut ? theme.colorScheme.error : status.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        // 15% fill and a 40% border, per the shared component spec — a solid
        // status fill would shout louder than the item's own name.
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
