/// The keyboard stand-in for a camera.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/ui/theme.dart';

/// What [promptForCode] came back with.
typedef CodeEntry = ({String code, double amount});

/// Asks for a barcode, and optionally how much one scan of it is worth.
///
/// **Typed, not scanned, on purpose — for now.** A camera scanner means a
/// platform-channel plugin, and platform-channel code cannot run in a VM test
/// binary, so every line of it would land in `COVERAGE_EXEMPT` and stop being
/// checked by anything. The repository API this feeds
/// (`linkBarcode` / `applyScan`) is the seam a scanner plugs into later
/// without touching any of the logic below it — which is the part worth
/// protecting.
Future<CodeEntry?> promptForCode(
  BuildContext context, {
  required IconData icon,
  required String semanticLabel,
  bool withAmount = false,
}) => showDialog<CodeEntry>(
  context: context,
  builder: (_) => _CodeDialog(
    icon: icon,
    semanticLabel: semanticLabel,
    withAmount: withAmount,
  ),
);

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({
    required this.icon,
    required this.semanticLabel,
    required this.withAmount,
  });

  final IconData icon;
  final String semanticLabel;
  final bool withAmount;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  final _amount = TextEditingController(text: '1');

  @override
  void dispose() {
    _code.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    // A blank or unparseable amount means one. Refusing to close over a typo
    // in a field most users will never touch would be worse than the sane
    // default, and `linkBarcode` rejects a non-positive amount anyway.
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop((code: code, amount: amount ?? 1));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Icon(widget.icon, semanticLabel: widget.semanticLabel),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('code_prompt_barcode'),
          controller: _code,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(
              Icons.qr_code_scanner_outlined,
              semanticLabel: 'Barcode',
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (widget.withAmount) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('code_prompt_amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.attach_money,
                semanticLabel: 'One scan is worth',
              ),
            ),
          ),
        ],
      ],
    ),
    actions: [
      IconButton(
        key: const Key('code_prompt_cancel'),
        icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      IconButton(
        key: const Key('code_prompt_ok'),
        icon: const Icon(Icons.check, semanticLabel: 'OK'),
        onPressed: _submit,
      ),
    ],
  );
}
