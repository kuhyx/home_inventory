/// When sync runs by itself: on launch, after a local write, on a timer, and
/// again after a failure, all without a tap.
///
/// Offline-first: every write already landed in the local log before any of
/// this runs, so a failed tick loses nothing. It only means "try again later".
/// What a tick does is the runner's business; this class only decides when.
library;

import 'dart:async';
import 'dart:developer';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:home_inventory/data/item_repository.dart';

/// How one background tick ended.
enum AutoSyncResult {
  /// Pulled, merged and pushed.
  synced,

  /// Nothing to do: no backend set up, or the passphrase is missing. Not
  /// retried on a timer; the next launch, resume or write tries again.
  skipped,

  /// The network or a backend failed. Retried on a backoff timer.
  failed,
}

/// Runs one tick and reports how it ended.
typedef AutoSyncRunner = Future<AutoSyncResult> Function();

/// Schedules background sync ticks over one repository.
class AutoSync {
  /// Creates a scheduler; nothing runs until [start].
  AutoSync({
    required this.repository,
    required this.run,
    this.debounce = const Duration(seconds: 3),
    this.firstRetry = const Duration(seconds: 30),
    this.maxRetry = const Duration(minutes: 15),
    this.interval = const Duration(minutes: 15),
  });

  /// Store whose writes trigger a tick.
  final ItemRepository repository;

  /// One tick.
  final AutoSyncRunner run;

  /// Quiet time after a write before it is pushed, so a burst of edits is
  /// one tick rather than one per keystroke.
  final Duration debounce;

  /// Wait before the first retry; doubles per failure up to [maxRetry].
  final Duration firstRetry;

  /// Longest wait between retries.
  final Duration maxRetry;

  /// Pull period while the app stays open, so a peer's edits arrive on a
  /// desktop that is never backgrounded.
  final Duration interval;

  StreamSubscription<void>? _changes;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Timer? _periodic;
  late Duration _retryDelay = firstRetry;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// The log as last pushed, so the change event a tick's own merge fires
  /// does not start another tick.
  String? _pushed;

  /// Starts listening for writes and runs the launch tick.
  void start() {
    _changes = repository.changes.listen((_) => syncSoon());
    _periodic = Timer.periodic(interval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  /// Runs a tick after [debounce] of quiet, if the log changed since the
  /// last push.
  void syncSoon() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (logToJson(repository.exportLog()) == _pushed) return;
      unawaited(syncNow());
    });
  }

  /// Runs a tick now. Never overlaps: a call during a running tick runs one
  /// more right after it, which is what pushes a write made mid-tick.
  Future<void> syncNow() async {
    if (_disposed) return;
    _debounceTimer?.cancel();
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        _retryTimer?.cancel();
        final before = logToJson(repository.exportLog());
        final result = await _runGuarded();
        if (_disposed) return;
        _settle(result, before);
      } while (_again);
    } finally {
      _running = false;
    }
  }

  /// Cancels every timer and stops listening. Safe to call twice.
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _periodic?.cancel();
    unawaited(_changes?.cancel());
  }

  /// Runs one tick; anything it throws is logged and counts as a failure,
  /// so the backoff retry is armed. That includes a Dart Error: a garbled
  /// response breaks a cast with a TypeError, and catching only Exception
  /// left such a tick with no retry until the next write or resume.
  Future<AutoSyncResult> _runGuarded() async {
    try {
      return await run();
    } on Object catch (error, stack) {
      log(
        'background sync failed: $error',
        name: 'home_inventory.sync',
        error: error,
        stackTrace: stack,
      );
      return AutoSyncResult.failed;
    }
  }

  void _settle(AutoSyncResult result, String before) {
    switch (result) {
      case AutoSyncResult.synced:
        _pushed = before;
        _retryDelay = firstRetry;
      case AutoSyncResult.failed:
        _retryTimer = Timer(_retryDelay, () => unawaited(syncNow()));
        final doubled = _retryDelay * 2;
        _retryDelay = doubled > maxRetry ? maxRetry : doubled;
      case AutoSyncResult.skipped:
        break;
    }
  }
}
