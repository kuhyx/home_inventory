/// The seam the sync layer and the backup files talk to.
part of 'item_repository.dart';

/// Exporting, importing and merging the raw CRDT log.
extension LogTransfer on ItemRepository {
  /// The whole log, to hand to `syncLog`.
  Log exportLog() => _store.snapshot();

  /// Merges [remote] into the local log.
  Future<void> importLog(Log remote) =>
      _store.replaceAll(mergeLogs(_store.snapshot(), remote));

  /// Replaces the whole log, e.g. with a post-merge result from `syncLog`.
  Future<void> replaceAll(Log merged) => _store.replaceAll(merged);

  /// The whole log as JSON text, for a manual backup.
  ///
  /// Deliberately the raw CRDT log rather than a prettied list of items: the
  /// quantity history and every field's clock come with it, so re-importing a
  /// backup is a lossless merge instead of a reset to whatever the file said.
  String exportJson() => logToJson(exportLog());

  /// Merges a backup produced by [exportJson] into the local log.
  ///
  /// A **merge**, never a replace. Restoring a month-old backup must not undo
  /// this month's edits, and per-record clocks already decide which side of
  /// each field wins.
  ///
  /// Throws [FormatException] on text that is not JSON. Malformed-but-valid
  /// JSON surfaces as a `TypeError` from `logFromJson`, so the settings
  /// screen's import action catches both rather than only `Exception`.
  Future<void> importJson(String text) => importLog(logFromJson(text));

  /// Drops adjustments past the retention horizon, persisting only if
  /// something actually changed.
  Future<void> pruneHistory({DateTime? now}) async {
    final snapshot = _store.snapshot();
    final pruned = dropAncientAdjustments(snapshot, now ?? DateTime.now());
    if (pruned.length != snapshot.length) await _store.replaceAll(pruned);
  }
}
