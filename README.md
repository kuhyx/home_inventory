# home_inventory

Offline-first inventory of everything in the house — books, PC parts, cables,
food, clothes, furniture, cleaning supplies — answering four questions:

1. **What do I have?** — searchable list of every item.
2. **What is running low?** — a per-item threshold, plus an optional
   "~9 days left" projection where there is enough usage history to justify one.
3. **Where is it?** — a place tree of any depth, e.g.
   `korytarz › szafka z lewej › najwyższa półka › sekcja przy drzwiach`.
4. **What do I need, and what can I sell?** — `wanted` / `sellable` flags.

Flutter, targeting **Android and web only**. The desktop app is the web build
served by a local wrapper in a Chrome `--app` window; Flutter's Linux embedder
manages ~20fps at 4K where the same Dart in Chrome sustains ~144fps. Do not run
`flutter create --platforms linux` here.

Data syncs peer-to-peer through the private `kuhyx/syncs` GitHub repo used as
dumb file storage (prefix `inventory-sync/`), via the shared
[`crdt_sync`](https://github.com/kuhyx/utils) library.

## How the data model works

Items are stored as **per-field last-writer-wins** CRDT records, so a phone
decrementing a quantity and a desktop correcting the same item's location both
survive the merge.

Last-writer-wins keeps only the newest value, though — writing `quantity`
destroys its own history. So every quantity change also appends an **immutable
`adjustment` record** to the same log. Those never change after creation, which
makes merging them trivially correct (ids are uuids, so merge is set union).
The consumption-rate projection reads that history.

Each adjustment records **why** the quantity moved (`use` / `restock` /
`correction` / `initial`), taken from which control the user touched. That
matters: without it, recounting a shelf and finding 6 where the app said 10 is
indistinguishable from four days of consumption, and the estimated burn rate
roughly quadruples. Only `use` feeds the rate.

Adjustments older than 180 days are pruned. The pruner is a pure function of
each record's own immutable content, which is what makes it converge across
devices — and it must run inside the `decode` hook of `syncLog`, not only on
load. Pruning locally alone would let a peer's stale file re-introduce a record
that then gets pushed straight back, committing churn on every sync forever.

## Screens

Three destinations in an `IndexedStack`, so each keeps its scroll position and
in-flight search across tab switches:

- **Items** — search, filter sheet (facet count on the badge), sort menu,
  summary strip, add FAB.
- **Locations** — the place tree with counts, nested as deeply as you like,
  with add / rename / move / delete. Tapping a row filters the Items tab,
  which is why `HomeShell` owns that filter rather than `ItemsScreen`.
  Rows are flattened to the *visible* ones and fed to a `ListView.builder`
  rather than nested `ExpansionTile`s, which would build a widget per node
  at every depth even while collapsed.
- **Shopping** — *To buy* (not fully stocked **or** wanted — a union, which is
  why it is a repository method and not an `ItemFilter`) and *To sell*, with a
  one-tap "bought one" restock and undo.

## Commands

```bash
bash scripts/ci_mirror.sh        # everything CI runs; also the pre-push hook
flutter test --coverage          # 100% line coverage is a hard gate
lcov --summary coverage/lcov.info
flutter analyze --fatal-infos --fatal-warnings
dart format lib/ test/ tool/ bin/
flutter build apk --release      # phone
flutter build web --release      # desktop (served by the wrapper)
```

100% line coverage is a hard gate, and `ci_mirror.sh` also checks that every
file under `lib/` actually *appears* in `lcov.info`. Without that second check
the first one fails open: a file no test imports is missing from the report
entirely rather than reported at 0%, so deleting a test file can raise the
percentage. The only permitted absences are the `COVERAGE_EXEMPT` list in that
script — three files with no executable lines, plus the two browser-only ones
that cannot compile into a VM test binary — and an entry that goes stale (the
file gains coverage, or disappears) fails the build too.

## Desktop

```bash
./run.sh                         # build the web bundle and open the app window
./install_arch.sh                # build, package and install via pacman
bash desktop/install_desktop_entry.sh   # launcher icon + .desktop entry only
```

`bin/home_inventory_desktop.dart` is orchestration only — spawning, stdout,
exit codes. Every decision it makes (argument parsing, which browser to launch,
and the profile/log paths, which must stay stable because the inventory lives
in that profile's IndexedDB) is in `lib/desktop/launcher.dart`, where tests can
reach it. The port comes from `lib/sync/desktop_wrapper.dart` rather than a
second constant, so the two cannot drift apart.

`run.sh` deliberately installs no GTK toolchain: there is no `linux/` embedder
directory here and never will be. Icons under `desktop/icons/` are pre-rendered
and committed; regenerate with

```bash
PYTHONPATH=~/testsAndMisc python3 -m python_pkg.app_icons \
    generate --app home_inventory --linux-out desktop/icons
```

Deploy to the phone with the shared script — never uninstall, it wipes data:

```bash
bash ~/.claude/scripts/phone_deploy.sh ~/home_inventory --release --shot /tmp/shot.png
```

## Places

Locations are their own CRDT record (`kTypeLocation`), not strings on an item,
which is what lets a room exist before anything is in it and makes a rename one
write instead of a rewrite of every item filed there. An item carries a
`location_id`; the legacy `room`/`container` strings are still written so a
device on an older build keeps showing places during the rollout, and get
deleted once every device is updated.

**Ids are derived, never minted.** `derivedLocationId(parentId, name)` is a
uuid v5 over a frozen namespace, so two devices that fold `room: 'Kitchen'`
into a record — or that both have the user type "Garage" while offline —
produce the *same* id and the merge is a no-op. A `v4` on each side would give
two Kitchens with nothing left to tell they were meant to be one. The id is
keyed to the name a place was born with, so renaming does not change it: think
birth certificate, not current name. The cost is that two same-named siblings
under one parent would collapse onto one record, so the create UI rejects a
duplicate sibling name.

**Cycles are broken on read, not just refused on write.** `moveLocation`
refuses a move into the mover's own subtree, but that guard cannot see a
concurrent move on another device: this device puts A under B while the other
puts B under A, each write wins its own field, and the merged graph loops.
`locationTree()` therefore walks down from the roots with a visited set and
re-roots anything it never reached, which is deterministic and so agrees across
devices. Deleting never cascades — a sticky delete plus a cascade means one
mis-tap removes a whole branch everywhere, with no undo — so children resurface
at the top level and items filed in a deleted place read as unfiled.

The migration that folds legacy strings into records runs on open and after
every sync (a peer on an old build can push un-migrated items), but **not**
inside `syncLog`'s `decode` hook: unlike pruning it *adds* records, and adding
there would grow the merge input on every tick.

## Conventions

- `analysis_options.yaml` is copied verbatim from `~/diet-guard/app`
  (`very_good_analysis`); never `flutter_lints`.
- Design tokens live in `lib/ui/theme.dart`, from the shared
  `unified-design-system`. Never `ColorScheme.fromSeed`, and no raw colour
  literals outside that file.
- **No `dart:io` reachable from `lib/main.dart`.** Platform-specific code goes
  behind a conditional export (`repository_factory{,_io,_web}.dart`); a single
  stray import breaks the web compile.
- Commit straight to `main`; no feature branches, no PRs.
- `@immutable` comes from `package:meta`, never `package:flutter/foundation.dart`:
  the models are reachable from `tool/sync_smoke.dart`, which runs under plain
  `dart run` and cannot load the Flutter SDK.
- Backups export the **raw CRDT log**, and importing one is a merge, not a
  restore — the per-field clocks decide each winner, so a stale backup cannot
  undo newer edits.
