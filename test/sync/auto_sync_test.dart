import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/data/item_repository.dart';
import 'package:home_inventory/sync/auto_sync.dart';

import '../support/builders.dart';

/// A runner that records each call and answers from [results], one per call
/// (the last answer repeats).
class _Runner {
  _Runner(this.results);

  final List<AutoSyncResult> results;
  int calls = 0;

  /// Applied to the repository during a run, as a real tick's merge would.
  Future<void> Function()? duringRun;

  Future<AutoSyncResult> call() async {
    final answer = results[calls < results.length ? calls : results.length - 1];
    calls++;
    await duringRun?.call();
    return answer;
  }
}

void main() {
  final at = DateTime.utc(2026, 11, 27);
  const debounce = Duration(seconds: 3);
  const firstRetry = Duration(seconds: 30);

  /// Runs [body] in fake time over a fresh in-memory store and an
  /// [AutoSync] driven by [runner], disposing it afterwards.
  void withAutoSync(
    _Runner runner,
    void Function(FakeAsync clock, ItemRepository repo, AutoSync auto) body,
  ) {
    fakeAsync((clock) {
      late ItemRepository repo;
      unawaited(ItemRepository.openInMemory().then((r) => repo = r));
      clock.flushMicrotasks();
      final auto = AutoSync(
        repository: repo,
        run: runner.call,
        debounce: debounce,
        firstRetry: firstRetry,
        maxRetry: const Duration(minutes: 2),
        interval: const Duration(hours: 1),
      )..start();
      clock.flushMicrotasks();
      body(clock, repo, auto);
      auto.dispose();
      unawaited(repo.close());
      clock.flushMicrotasks();
    });
  }

  void write(FakeAsync clock, ItemRepository repo, String id) {
    unawaited(repo.upsert(itemFixture(id: id, name: id, updatedAt: at)));
    clock.flushMicrotasks();
  }

  test('syncs once on launch without a tap', () {
    final runner = _Runner([AutoSyncResult.synced]);
    withAutoSync(runner, (clock, repo, auto) {
      expect(runner.calls, 1);
    });
  });

  test('a burst of local writes is pushed by one debounced sync', () {
    final runner = _Runner([AutoSyncResult.synced]);
    withAutoSync(runner, (clock, repo, auto) {
      write(clock, repo, 'a');
      clock.elapse(const Duration(seconds: 1));
      write(clock, repo, 'b');
      clock.elapse(const Duration(seconds: 2));
      expect(runner.calls, 1, reason: 'still inside the debounce');
      clock.elapse(debounce);
      expect(runner.calls, 2);
    });
  });

  test('the merge a sync writes back does not start another sync', () {
    final runner = _Runner([AutoSyncResult.synced]);
    withAutoSync(runner, (clock, repo, auto) {
      // The tick's own replaceAll fires the change stream, exactly as a
      // merge with nothing new from peers does.
      runner.duringRun = () => repo.replaceAll(repo.exportLog());
      write(clock, repo, 'a');
      clock.elapse(debounce * 10);
      expect(runner.calls, 2, reason: 'one for launch, one for the write');
    });
  });

  test('a failed sync keeps the write and retries without a tap', () {
    final runner = _Runner([
      AutoSyncResult.synced,
      AutoSyncResult.failed,
      AutoSyncResult.failed,
      AutoSyncResult.synced,
    ]);
    withAutoSync(runner, (clock, repo, auto) {
      write(clock, repo, 'a');
      clock.elapse(debounce);
      expect(runner.calls, 2);
      expect(repo.item('a'), isNotNull, reason: 'the write stays local');

      clock.elapse(firstRetry);
      expect(runner.calls, 3, reason: 'first retry');
      clock.elapse(firstRetry);
      expect(runner.calls, 3, reason: 'the second retry waits twice as long');
      clock.elapse(firstRetry);
      expect(runner.calls, 4);

      // Success clears the retry: nothing more runs until something happens.
      clock.elapse(const Duration(minutes: 10));
      expect(runner.calls, 4);
      expect(repo.item('a'), isNotNull);
    });
  });

  test('a runner that throws counts as a failure and is retried', () {
    var calls = 0;
    fakeAsync((clock) {
      late ItemRepository repo;
      unawaited(ItemRepository.openInMemory().then((r) => repo = r));
      clock.flushMicrotasks();
      final auto = AutoSync(
        repository: repo,
        run: () async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return AutoSyncResult.synced;
        },
        firstRetry: firstRetry,
      )..start();
      clock
        ..flushMicrotasks()
        ..elapse(firstRetry);
      expect(calls, 2);
      auto.dispose();
    });
  });

  test('a skipped sync (not set up) is not retried on a timer', () {
    final runner = _Runner([AutoSyncResult.skipped]);
    withAutoSync(runner, (clock, repo, auto) {
      clock.elapse(const Duration(minutes: 30));
      expect(runner.calls, 1);
    });
  });

  test('syncs on the periodic timer while the app stays open', () {
    final runner = _Runner([AutoSyncResult.synced]);
    withAutoSync(runner, (clock, repo, auto) {
      clock.elapse(const Duration(hours: 2));
      expect(runner.calls, 3);
    });
  });

  test('never overlaps; a write during a sync is pushed right after', () {
    final runner = _Runner([AutoSyncResult.synced]);
    withAutoSync(runner, (clock, repo, auto) {
      // Created inside fake time, or its completion is a real microtask.
      final gate = Completer<void>();
      runner.duringRun = () => gate.future;
      unawaited(auto.syncNow());
      clock.flushMicrotasks();
      expect(runner.calls, 2);
      unawaited(auto.syncNow());
      write(clock, repo, 'a');
      clock.elapse(debounce);
      expect(runner.calls, 2, reason: 'the first tick is still running');
      runner.duringRun = null;
      gate.complete();
      clock.flushMicrotasks();
      expect(runner.calls, 3);
    });
  });

  test('dispose stops every timer', () {
    final runner = _Runner([AutoSyncResult.failed]);
    withAutoSync(runner, (clock, repo, auto) {
      auto.dispose();
      write(clock, repo, 'a');
      clock.elapse(const Duration(hours: 3));
      expect(runner.calls, 1);
      unawaited(auto.syncNow());
      clock.flushMicrotasks();
      expect(runner.calls, 1);
    });
  });
}
