/// Adjustment glyphs & text — extracted from [ItemDetailScreen] to keep it
/// under the 250-line limit.
library;

import 'package:home_inventory/models/adjustment.dart';
import 'package:home_inventory/models/barcode_link.dart';
import 'package:home_inventory/models/item.dart';
import 'package:material_ui/material_ui.dart';

/// Icon for an adjustment source.
IconData adjustmentSourceGlyph(AdjustmentSource source) {
  switch (source) {
    case AdjustmentSource.use:
      return Icons.remove_circle_outline;
    case AdjustmentSource.restock:
      return Icons.add_circle_outline;
    case AdjustmentSource.correction:
      return Icons.edit_outlined;
    case AdjustmentSource.initial:
      return Icons.flag_outlined;
  }
}

/// Tooltip for an adjustment source (textgate: one word).
String adjustmentSourceTooltip(AdjustmentSource source) {
  switch (source) {
    case AdjustmentSource.use:
      return 'Consumed';
    case AdjustmentSource.restock:
      return 'Restocked';
    case AdjustmentSource.correction:
      return 'Corrected';
    case AdjustmentSource.initial:
      return 'Initial';
  }
}

/// Zero-padded two-digit string.
String adjustTwo(int n) => n.toString().padLeft(2, '0');

/// "+N unit" string for a barcode link.
String adjustPerScan(BarcodeLink link) {
  final unit = link.unit.isEmpty ? '' : ' ${link.unit}';
  if (link.amount == 1) return '+1$unit';
  return '+${formatQuantity(link.amount)}$unit';
}

/// Signed quantity string for an adjustment (matches original _signed).
String adjustSigned(Adjustment a) =>
    '${a.delta < 0 ? '−' : '+'}${formatQuantity(a.delta.abs())}';

/// Semantic description for an adjustment (matches original _describe).
String adjustDescribe(Adjustment a) {
  final amount = formatQuantity(a.delta.abs());
  return switch (a.source) {
    AdjustmentSource.use => 'Used $amount',
    AdjustmentSource.restock => 'Added $amount',
    AdjustmentSource.correction =>
      'Recounted to ${a.delta > 0 ? '+' : '−'}$amount',
    AdjustmentSource.initial => 'Added $amount to start',
  };
}
