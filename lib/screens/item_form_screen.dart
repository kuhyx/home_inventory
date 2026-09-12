/// The full add/edit form — everything the quick-add sheet leaves out.
library;

import 'package:flutter/material.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/ui/location_field.dart';
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
    _bestBefore = TextEditingController(text: _formatDate(item?.bestBefore));
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

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  /// The one date shape the field accepts, and the one it writes back.
  ///
  /// ISO order rather than anything local: it sorts as text, it is
  /// unambiguous between the Polish and English readings of `03/04`, and it
  /// is what the CRDT record already stores.
  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _formatDate(DateTime? date) => date == null
      ? ''
      : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';

  /// Parses the field, or null for blank **and** for anything malformed.
  ///
  /// The round-trip check is the whole point. `DateTime.parse` does not
  /// reject an impossible date — it rolls it over, quietly turning
  /// `2026-13-45` into 2027-02-14 — so parsing alone would store a date the
  /// user never typed and then show it back to them as if they had.
  static DateTime? _parseDate(String text) {
    final trimmed = text.trim();
    if (!_isoDate.hasMatch(trimmed)) return null;
    final parsed = DateTime.tryParse(trimmed);
    return parsed != null && _formatDate(parsed) == trimmed ? parsed : null;
  }

  /// Opens the calendar and writes the chosen day back into the field.
  ///
  /// Typing stays available alongside it: the picker is faster for "next
  /// Tuesday" and unbearable for "March 2028", and the field is the one
  /// source of truth either way.
  Future<void> _pickDate() async {
    final current = _parseDate(_bestBefore.text);
    final anchor = (widget.now ?? DateTime.now)();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? anchor,
      firstDate: DateTime(anchor.year - 5),
      lastDate: DateTime(anchor.year + 20),
    );
    if (picked == null) return;
    setState(() => _bestBefore.text = _formatDate(picked));
  }

  String? _validateDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!_isoDate.hasMatch(text)) return 'Use YYYY-MM-DD';
    if (_parseDate(text) == null) return 'Not a real date';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final at = (widget.now ?? DateTime.now)();
    final quantity = _parse(_quantity.text) ?? 0;
    final threshold = _lowStockAt.text.trim().isEmpty
        ? null
        : _parse(_lowStockAt.text);
    final existing = _existing;
    final locationId = await _resolveLocationId(at);
    // The legacy strings stay written for as long as a device on an older
    // build might read them: that build knows nothing of `location_id`, and
    // an empty `room` there reads as an item that lost its place.
    final path = widget.repository.pathOf(locationId);
    final item = Item(
      id: existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      quantity: quantity,
      unit: _unit.text.trim(),
      locationId: locationId,
      room: path.isEmpty ? '' : path.first,
      container: path.length > 1 ? path.skip(1).join(' › ') : '',
      category: _category.text.trim(),
      lowStockAt: threshold,
      bestBefore: _parseDate(_bestBefore.text),
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

  /// The place to file this item under, creating the records an item that
  /// predates the places tree still only names as strings.
  ///
  /// The ids are the same ones `planLocationMigration` would derive —
  /// `createLocation` is a pure function of (parent, folded name) — so filing
  /// it here early converges with a device that gets there via the migration
  /// instead. Doing it on save rather than on open keeps the form from
  /// writing to the log just because it was looked at.
  Future<String> _resolveLocationId(DateTime at) async {
    if (_locationPicked || _locationId.isNotEmpty) return _locationId;
    final room = _existing?.room.trim() ?? '';
    if (room.isEmpty) return '';
    final repo = widget.repository;
    final roomPlace = await repo.createLocation(name: room, now: at);
    final container = _existing?.container.trim() ?? '';
    if (container.isEmpty) return roomPlace.id;
    final inner = await repo.createLocation(
      name: container,
      parentId: roomPlace.id,
      now: at,
    );
    return inner.id;
  }

  Future<void> _delete() async {
    final item = _existing;
    if (item == null) return;
    await widget.repository.delete(item.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String? _validateNumber(String? value, {required bool required}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return required ? 'Enter a number' : null;
    final parsed = _parse(text);
    if (parsed == null) return 'Not a number';
    if (parsed < 0) return 'Cannot be negative';
    return null;
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
              validator: (value) => _validateNumber(value, required: true),
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
              validator: (value) => _validateNumber(value, required: false),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SuggestField(
                    controller: _bestBefore,
                    label: 'Best before (YYYY-MM-DD, blank for never)',
                    keyboardType: TextInputType.datetime,
                    textCapitalization: TextCapitalization.none,
                    validator: _validateDate,
                  ),
                ),
                IconButton(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  tooltip: 'Pick a date',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SuggestField(
              controller: _notes,
              label: 'Notes',
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              value: _wanted,
              onChanged: (value) => setState(() => _wanted = value),
              title: const Text('I want this'),
              subtitle: const Text('Keeps it on the buy list'),
            ),
            SwitchListTile(
              value: _sellable,
              onChanged: (value) => setState(() => _sellable = value),
              title: const Text('I could sell this'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
