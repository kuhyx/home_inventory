/// The mapping from a scanned code to an item, and how much one scan means.
library;

import 'package:home_inventory/data/derived_ids.dart';

/// One barcode, pointing at one item, worth a fixed amount.
///
/// The amount is the whole reason this is a record rather than a string field
/// on [Item]: a 500 g bag of flour and a 1 kg bag have different codes, and
/// scanning either has to add what is actually in the bag. Grocy learned this
/// the same way — a barcode that means "+1 of something" is only useful for
/// the items you happen to buy in a single size.
class BarcodeLink {
  /// Creates a link.
  const BarcodeLink({
    required this.code,
    required this.itemId,
    required this.amount,
    required this.unit,
  });

  /// The normalised code, as [normalizeBarcode] returns it.
  final String code;

  /// The item this code stocks.
  final String itemId;

  /// How much one scan adds. Never zero — a link that changes nothing is a
  /// link the user would scan twice and then assume was broken.
  final double amount;

  /// The unit [amount] is counted in, recorded at link time.
  ///
  /// Informational only: the item owns its unit, and a link that disagreed
  /// with it would be a second source of truth. Stored so a later "500 g"
  /// label can be shown next to the code without re-deriving it.
  final String unit;

  /// The CRDT record id for [code].
  ///
  /// **Derived from the code, not minted.** Two devices that scan the same
  /// unknown bag and link it to the same item must converge on one mapping;
  /// with random ids they would each keep their own, and a lookup would have
  /// to pick between two records that both claim the code.
  ///
  /// A uuid v5 rather than a `barcode-$code` prefix, so the record id stays an
  /// opaque key: `record_types.dart` keeps the kind in a field precisely so
  /// that recognising a kind is an equality check and never string parsing.
  /// Pass a code already folded by [normalizeBarcode].
  static String recordId(String code) => derivedBarcodeId(code);

  /// Folds the variants of one physical code onto a single string.
  ///
  /// A UPC-A code is the same product as the EAN-13 that starts with a zero —
  /// scanners on different phones disagree about which one they report, and a
  /// household that scans a US-labelled tin twice would otherwise get two
  /// mappings for one tin. Non-numeric codes are left alone beyond trimming:
  /// QR labels are not GTINs and must not be padded.
  static String normalizeBarcode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length != 12) return trimmed;
    return RegExp(r'^\d{12}$').hasMatch(trimmed) ? '0$trimmed' : trimmed;
  }

  @override
  String toString() =>
      'BarcodeLink($code -> $itemId, +$amount${unit.isEmpty ? '' : ' $unit'})';
}
