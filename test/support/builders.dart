import 'package:home_inventory/models/item.dart';
import 'package:home_inventory/models/location.dart';

/// A fully-specified item, so each test overrides only what it cares about.
Item itemFixture({
  String id = 'i1',
  String name = 'Thing',
  double quantity = 1,
  String unit = '',
  String locationId = '',
  String room = '',
  String container = '',
  String category = '',
  double? lowStockAt,
  DateTime? bestBefore,
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
  locationId: locationId,
  room: room,
  container: container,
  category: category,
  lowStockAt: lowStockAt,
  bestBefore: bestBefore,
  wanted: wanted,
  sellable: sellable,
  notes: notes,
  createdAt: createdAt ?? DateTime.utc(2026),
  updatedAt: updatedAt ?? createdAt ?? DateTime.utc(2026),
);

/// A fully-specified location, so each test overrides only what it cares
/// about. The id defaults to a literal rather than a derived one: most tests
/// care about the shape of the tree, not how ids are minted.
Location locationFixture({
  String id = 'loc1',
  String name = 'Somewhere',
  String? parentId,
  double sortKey = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Location(
  id: id,
  name: name,
  parentId: parentId,
  sortKey: sortKey,
  createdAt: createdAt ?? DateTime.utc(2026),
  updatedAt: updatedAt ?? createdAt ?? DateTime.utc(2026),
);
