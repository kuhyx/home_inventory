/// Record ids that two devices can mint independently and still agree on.
library;

import 'package:uuid/uuid.dart';

/// Namespace for every derived id in this app.
///
/// A frozen uuid v4, generated once. **Never regenerate it.** Every location
/// and item-type id is a v5 hash of this value plus a name, so changing it
/// repartitions every tree on every device at once — old records keep their
/// old ids, new ones get new ones, and the two never merge again.
const String kInventoryNamespace = '8d9852da-d70a-455d-9ad6-d0189d6efdda';

/// Case- and whitespace-folded form of [name], used as the id input.
///
/// Deliberately dumb, because two devices have to agree on it byte for byte:
/// trim the ends, collapse internal runs of whitespace, lowercase. Anything
/// cleverer (unicode normalisation, stripping punctuation) is a rule that a
/// future edit could change, and changing it silently repartitions the tree.
String foldKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The id of the location called [name] under [parentId].
///
/// Derived rather than minted, and that is the whole migration story. Two
/// devices that both fold `room: 'Kitchen'` into a location record — or that
/// both have the user type "Garage" while offline — produce the *same* id, so
/// the merge is per-field last-writer-wins over identical content: a no-op.
/// A `Uuid().v4()` on each side would instead produce two Kitchens with no
/// way left to tell they were ever meant to be one.
///
/// The id is keyed to the name a location was *born* with, so renaming cannot
/// change it. That is fine — the name is an ordinary last-writer-wins field.
/// Think of the id as a birth certificate, not a current name.
///
/// Two genuinely distinct siblings sharing a name under one parent collapse
/// onto one id. The create UI rejects duplicate sibling names for that reason.
String derivedLocationId(String? parentId, String name) => const Uuid().v5(
  kInventoryNamespace,
  'loc:${parentId ?? ''}/${foldKey(name)}',
);

/// The id of the built-in item type identified by [slug].
///
/// Same reasoning as [derivedLocationId]: seeding the default types on two
/// devices writes identical records, so seeding is idempotent by construction
/// rather than by a guard.
String derivedItemTypeId(String slug) =>
    const Uuid().v5(kInventoryNamespace, 'type:${foldKey(slug)}');
