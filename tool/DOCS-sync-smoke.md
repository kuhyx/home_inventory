# `tool/sync_smoke.dart` — checking sync against real GitHub

A manual, against-real-GitHub check that sync actually works. Not part of the
test suite: it talks to the network.

```
Usage, from the repo root:

  GITHUB_TOKEN=<pat> dart run tool/sync_smoke.dart
  GITHUB_TOKEN=<pat> dart run tool/sync_smoke.dart --seed "Test cable"

Pass --seed to push one throwaway item; run it again without --seed (which
gets a fresh node id) and that item should come back. That two-run pair is
what actually proves a round trip — a bare run only proves the push half.

`--dir` turns this into a *persistent* peer instead: a stable node id and a
store that survives between runs, which is what the convergence checks need.
One-shot runs cannot express "edit, then sync later", and that gap is
exactly where per-field LWW either works or silently does not:

  # reverse direction (PC -> phone)
  ... --dir /tmp/peer --seed "Sync check"
  # then tap Sync on the phone; the item should appear

  # concurrent edits: change different fields on each side BEFORE syncing
  ... --dir /tmp/peer --set <id> room Workshop --no-sync
  # change the quantity on the phone, then sync both. Both must survive.

  # clean up
  ... --dir /tmp/peer --delete <id>

A stable node id writes a stable file in the syncs repo, so a peer directory
you are finished with leaves a slot behind; `--forget` deletes that file from
GitHub, which a throwaway run cannot do for itself.
```
