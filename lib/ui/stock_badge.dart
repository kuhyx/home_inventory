/// The low/out indicator shown next to an item.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/status_pill.dart';
import 'package:home_inventory/ui/theme.dart';

/// Glyph for each [StockState]: a battery draining, so the filter chips and
/// the list badges share one picture per state.
IconData stockGlyph(StockState state) => switch (state) {
  StockState.ok => Icons.battery_full,
  StockState.low => Icons.battery_2_bar,
  StockState.out => Icons.battery_0_bar,
};

/// Spoken-only name of each [StockState].
String stockSpoken(StockState state) => switch (state) {
  StockState.ok => 'In stock',
  StockState.low => 'Low',
  StockState.out => 'Out',
};

/// A small pill showing an item's [StockState], or nothing at all when the
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
    return StatusPill(
      icon: stockGlyph(state),
      color: isOut ? theme.colorScheme.error : status.warning,
      semanticLabel: stockSpoken(state),
    );
  }
}
