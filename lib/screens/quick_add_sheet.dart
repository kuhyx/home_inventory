/// The fast path for getting a thing into the inventory.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/location_field.dart';
import 'package:home_inventory/ui/suggest_field.dart';
import 'package:home_inventory/ui/theme.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet for adding an item in as few taps as possible.
///
/// Cataloguing a home means entering dozens of things in one sitting, so this
/// is tuned for repetition rather than completeness: name autofocused, a
/// quantity that defaults to 1, the place pre-filled, and a "Save & add
/// another" that keeps the keyboard up. Everything else (threshold, category,
/// notes) lives in the full form.
class QuickAddSheet extends StatefulWidget {
  /// Creates the sheet.
  const QuickAddSheet({
    required this.repository,
    this.initialLocationId,
    this.now,
    super.key,
  });

  /// Store to write into.
  final ItemRepository repository;

  /// Where to file this by default — the place the item list is currently
  /// filtered to. Standing in the hallway with the list showing the hallway,
  /// the next thing added is overwhelmingly in the hallway.
  final String? initialLocationId;

  /// Injectable clock, so tests get deterministic timestamps.
  final DateTime Function()? now;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '1');

  /// Where the next item goes, empty for "nowhere".
  late String _locationId;

  String? _error;

  @override
  void initState() {
    super.initState();
    // What the list is filtered to first, the busiest place second:
    // consecutive adds are usually in the same corner of the house, so this
    // is right far more often than it is wrong, and it is one tap to change.
    _locationId =
        widget.initialLocationId ?? widget.repository.mostUsedLocationId();
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  double? _parsedQuantity() {
    final text = _quantity.text.trim();
    if (text.isEmpty) return 1;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<bool> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    final quantity = _parsedQuantity();
    if (quantity == null || quantity < 0) {
      setState(() => _error = 'Quantity must be a number');
      return false;
    }
    final at = (widget.now ?? DateTime.now)();
    // Legacy strings alongside the id, for a device still on a build that
    // cannot read `location_id`. See `ItemFormScreen._save`.
    final path = widget.repository.pathOf(_locationId);
    await widget.repository.upsert(
      Item(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        quantity: quantity,
        unit: '',
        locationId: _locationId,
        room: path.isEmpty ? '' : path.first,
        container: path.length > 1 ? path.skip(1).join(' › ') : '',
        category: '',
        lowStockAt: null,
        bestBefore: null,
        wanted: false,
        sellable: false,
        notes: '',
        createdAt: at,
        updatedAt: at,
      ),
    );
    return true;
  }

  Future<void> _saveAndClose() async {
    if (!await _save()) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _saveAndContinue() async {
    if (!await _save()) return;
    if (!mounted) return;
    // Keep the place: the next thing is almost always in the same drawer.
    // Only the name and quantity reset.
    setState(() {
      _name.clear();
      _quantity.text = '1';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add an item',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              SuggestField(
                controller: _name,
                label: 'What is it?',
                autofocus: true,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Give it a name' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              SuggestField(
                controller: _quantity,
                label: 'How many?',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              LocationField(
                repository: repo,
                locationId: _locationId,
                now: widget.now,
                onChanged: (id) => setState(() => _locationId = id),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveAndContinue,
                      child: const Text('Save & add another'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveAndClose,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
