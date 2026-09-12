/// The full add/edit form — everything the quick-add sheet leaves out.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/data/legacy_location_filing.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/best_before_field.dart';
import 'package:home_inventory/ui/item_flag_switches.dart';
import 'package:home_inventory/ui/location_field.dart';
import 'package:home_inventory/ui/number_input.dart';
import 'package:home_inventory/ui/suggest_field.dart';
import 'package:home_inventory/ui/theme.dart';
import 'package:uuid/uuid.dart';

/// Add or edit one item, with every field exposed.
class ItemFormScreen extends StatefulWidget {
  /// Creates the form. A null [item] means "create a new one".
  const ItemFormScreen({
    required this.repository,
    this.item,
    this.now,
    super.key,
  });

  /// Store to write into.
  final ItemRepository repository;

  /// The item being edited, or null when creating.
  final Item? item;

  /// Injectable clock, so tests get deterministic timestamps.
  final DateTime Function()? now;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _category;
  late final TextEditingController _lowStockAt;
  late final TextEditingController _bestBefore;
  late final TextEditingController _notes;
  late bool _wanted;
  late bool _sellable;

  /// The place this item is filed under, empty for "nowhere".
  late String _locationId;

  /// Whether the user chose the place themselves in this session.
  ///
  /// Until they do, an item that predates the places tree is filed from its
  /// own legacy `room`/`container` strings on save. Afterwards their choice
  /// wins — including the explicit "not filed anywhere", which is otherwise
  /// indistinguishable from "untouched".
  bool _locationPicked = false;

  Item? get _existing => widget.item;

  @override
  void initState() {
    super.initState();
    final item = _existing;
    _name = TextEditingController(text: item?.name ?? '');
    _quantity = TextEditingController(
      text: item == null ? '1' : formatQuantity(item.quantity),
    );
    _unit = TextEditingController(text: item?.unit ?? '');
    _locationId = item?.locationId ?? '';
    _category = TextEditingController(text: item?.category ?? '');
    _lowStockAt = TextEditingController(
      text: item?.lowStockAt == null ? '' : formatQuantity(item!.lowStockAt!),
    );
    _bestBefore = TextEditingController(text: formatIsoDate(item?.bestBefore));
    _notes = TextEditingController(text: item?.notes ?? '');
    _wanted = item?.wanted ?? false;
    _sellable = item?.sellable ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _category.dispose();
    _lowStockAt.dispose();
    _bestBefore.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final at = (widget.now ?? DateTime.now)();
    final quantity = parseNumberInput(_quantity.text) ?? 0;
    final threshold = _lowStockAt.text.trim().isEmpty
        ? null
        : parseNumberInput(_lowStockAt.text);
    final existing = _existing;
    // An item that predates the places tree still names its place as two
    // strings; the user's own pick wins over them once they make one.
    final locationId = _locationPicked || _locationId.isNotEmpty
        ? _locationId
        : await fileLegacyStrings(
            widget.repository,
            room: _existing?.room ?? '',
            container: _existing?.container ?? '',
            at: at,
          );
    final legacy = legacyStringsFor(widget.repository.pathOf(locationId));
    final item = Item(
      id: existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      quantity: quantity,
      unit: _unit.text.trim(),
      locationId: locationId,
      room: legacy.room,
      container: legacy.container,
      category: _category.text.trim(),
      lowStockAt: threshold,
      bestBefore: parseIsoDate(_bestBefore.text),
      wanted: _wanted,
      sellable: _sellable,
      notes: _notes.text.trim(),
      createdAt: existing?.createdAt ?? at,
      updatedAt: at,
    );
    // A quantity typed into this form is a recount, never consumption — the
    // default source is `correction`, which is exactly what keeps a recount
    // from being read as usage by the rate projection.
    await widget.repository.upsert(item);
    if (!mounted) return;
    Navigator.of(context).pop(item);
  }

  Future<void> _delete() async {
    final item = _existing;
    if (item == null) return;
    await widget.repository.delete(item.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New item' : 'Edit item'),
        actions: [
          if (_existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SuggestField(
              controller: _name,
              label: 'Name',
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Give it a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(
              controller: _quantity,
              label: 'Quantity',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => validateNumberInput(value, required: true),
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(
              controller: _unit,
              label: 'Unit (blank for a plain count)',
              suggestions: repo.knownUnits(),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: AppSpacing.md),
            LocationField(
              repository: repo,
              locationId: _locationId,
              // A pre-places item shows its old strings until it is filed for
              // real, which happens on the next save either way.
              fallbackLabel: _locationPicked
                  ? ''
                  : (_existing?.legacyLocation ?? ''),
              now: widget.now,
              onChanged: (id) => setState(() {
                _locationId = id;
                _locationPicked = true;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(
              controller: _category,
              label: 'Category',
              suggestions: repo.knownCategories(),
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(
              controller: _lowStockAt,
              label: 'Warn me at (blank for never)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => validateNumberInput(value, required: false),
            ),
            const SizedBox(height: AppSpacing.md),
            BestBeforeField(
              controller: _bestBefore,
              now: widget.now ?? DateTime.now,
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(controller: _notes, label: 'Notes'),
            const SizedBox(height: AppSpacing.md),
            ItemFlagSwitches(
              wanted: _wanted,
              sellable: _sellable,
              onWantedChanged: (value) => setState(() => _wanted = value),
              onSellableChanged: (value) => setState(() => _sellable = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
