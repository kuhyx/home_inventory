import 'package:home_inventory/models/item.dart';

/// A fully-specified item, so each test overrides only what it cares about.
Item itemFixture({
  String id = 'i1',
  String name = 'Thing',
  double quantity = 1,
  String unit = '',
  String room = '',
  String container = '',
  String category = '',
  double? lowStockAt,
  bool wanted = false,
  bool sellable = false,
  String notes = '',
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Item(
  id: id,
  name: name,
  quantity: quantity,
  unit: unit,
  room: room,
  container: container,
  category: category,
  lowStockAt: lowStockAt,
  wanted: wanted,
  sellable: sellable,
  notes: notes,
  createdAt: createdAt ?? DateTime.utc(2026),
  updatedAt: updatedAt ?? createdAt ?? DateTime.utc(2026),
);
