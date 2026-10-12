# Development

## Layout

- `shell.qml`: service/window composition and `calendar.toggle` IPC.
- `common/`: event/profile validation, calendar layout and recurrence schema.
- `services/`: profile storage, range queries, persistence and conflict state.
- `ui/`: views, editor, details and conflict review.
- `parse/src/`: C++17/libical parser, recurrence expansion, ICS serialization,
  grouped transactions and conflict resolution.
- `parse/test/` and `dev/tests/`: native, shell, Node and actual Qt regressions.

Runtime helper paths remain `parse/convert`, `parse/calendar-sync-helper` and
`parse/conflict-broker.sh`. Generated objects, test executables and disposable
fixtures belong in ignored `parse/output/`.

`dev/`, `parse/test/`, `parse/.clangd` and module-local `AGENTS.md` files are local
development files and Git-ignored by maintainer choice. Client deployment excludes
them, prebuilt helpers and disposable artifacts. `docs/` and `.gitignore` stay in
Git but are excluded from deployment; clients retain `parse/src/`, Makefile,
runtime/deployment scripts and README links to online documentation.
Fresh Git clones/client installations therefore do not contain the tests below.
Keep the local test directories if you want continued automated development checks.

## Recurrence contract

Persist logical masters, not expanded occurrences. `OccurrenceRangeStore` requests
only the visible range when data/range changes; native libical expands it. Request
IDs/signatures reject stale results. No renewal task or background recurrence poll.

Authored rules have exactly `frequency`, `interval`, `startsOn`, `pattern`, `ends`:
the dates below are synthetic examples, not calendar data.

```json
{
  "frequency": "weekly",
  "interval": 2,
  "startsOn": "2030-01-03",
  "pattern": { "weekdays": [0, 2] },
  "ends": { "mode": "count", "count": 4 }
}
```

- Weekdays use Monday=0 through Sunday=6. Weekly cycles are Monday-start weeks.
- Daily pattern: `{}`. Weekly: `weekdays`. Monthly: `mode: "dates"` with `days`,
  or `mode: "positions"` with `{ordinal, weekday}` entries; ordinal is 1–5 or -1
  for last. Yearly: `dates` containing explicit `{month, day}` pairs.
- Daily/Weekly anchor to the selected date; Monthly to its first day; Yearly to
  January 1. Empty initial cycles retain their phase; normalization finds the
  first real occurrence without changing the rule's boundary.
- Interval/count are positive integers up to 2147483647. Endings are `never`,
  inclusive `date` with an ISO date, or total `count`. Until cannot precede boundary.
- Skip nonexistent dates, absent fifth weekdays and nonexistent DST start times.
  Deduplicate before COUNT; queries do not reset the count.
- Timed series preserve the saved creation timezone's start clock and initial
  elapsed duration; viewers display their own local time. Overnight initially ends
  next day. Authored All-day occupies one date, with exclusive next-date end.
- Edit/delete applies to the whole series. There is no occurrence-exception editor.

Imports retain ICS and honor supported RRULE, RDATE, EXDATE, RECURRENCE-ID and
cancellations. Supplied VTIMEZONE takes precedence; genuinely floating values use
the viewer's timezone. Nominal DURATION days/weeks advance source-zone dates before
elapsed hours/minutes/seconds. Explicit RDATE periods determine duration before
overlap filtering, so broad/narrow queries agree. Malformed/unsupported input warns
without rewriting source or inventing occurrences. Foreign rules the editor cannot
represent losslessly remain read-only.

Arbitrary Yearly pairs use standard per-pair ICS resources with grouping metadata,
not a cross-product RRULE. The combined union determines COUNT's inclusive cutoff;
stable logical/member identities survive edits. Complete compatible groups collapse
into one logical cache master. Missing/divergent/foreign members remain visible and
protected; rebuilding never repairs canonical sources silently.

Preserve unknown ICS properties, calendar envelopes, timezone components and opaque
alarms. Compare timezone components using normalized clones, not rewritten originals.
Changing all group dates transfers common opaque content; refuse changes that would
discard unique removed-member content. Group collapse has the same lossless policy.

Standards reference: [RFC 5545 recurrence sets](https://www.rfc-editor.org/rfc/rfc5545#section-3.8.5.3).

## Safety and cost boundaries

Grouped writes require paused sync, serialization/calendar locks, all-member stale
checks and a durable local journal. Failed/interrupted resolution retains startup
guards; local rollback does not establish remote rollback. Conflict choices cover
immutable whole-group snapshots; review every pair before applying. Clear conflict
only after canonical members and rebuilt cache verify. Ordinary routes cannot
bypass stored grouped ownership when metadata disappears.

Source sets are bounded separately before/after (16 MiB each including UIDs), with
a 64 MiB Base64 journal ceiling. Conflict snapshots use the same per-side source
budget. `conflict_limits.h` bounds encoded state, including duplicated/nested JSON
and protected previews; QML reader must stay compatible. The ceiling is not a
preallocation. CLI arguments and process output are validated before state changes.

Expansion has finite work/output limits. Ancient subdaily INTERVAL>1 rules iterate
from seed because libical seeking can alter cadence; hitting the cap fails safely.
Some zoned/nominal-duration rules need conservative lookback. Do not weaken limits
or introduce hand-written recurrence arithmetic to hide these ceilings.

View zoom uses wheel-only MouseAreas because WheelHandler ignores synthesized
wheel input. `acceptedButtons: Qt.NoButton` leaves clicks alone; `cursorShape:
undefined` resets cursor ownership so underlying cards retain hand cursors. Reject
non-Ctrl wheel events instead of scrolling manually. Actual Qt regressions cover
native/synthesized events and full view geometry, not only extracted callbacks.

Single-file imports retain a 2-second stability wait. Synced mutations rebuild the
full cache, O(number of ICS files), by design. Profile before introducing incremental
cache machinery. Some source-wiring tests remain spelling-sensitive; replace only
when equivalent behavioral coverage exists. Import registry/cache commits are not
a cross-file transaction. Native ICS mtimes can advance one second beyond previous
source to avoid older pimsync vdir etag misses; cache mtimes are unaffected.

## Checks

Build dependencies: C++17 compiler, Make, pkg-config, libical and Qt6Core. Tests add
Node.js, jq, pimsync and usual POSIX tools; Qt probes add Python/PySide6. From this
config directory:

```sh
make -C parse test
make -C parse lint
sh dev/tests/installer/test-installer.sh
sh dev/tests/installer/test-installer-sync.sh
sh dev/tests/installer/test-installer-import.sh
sh dev/tests/installer/test-update-bootstrap.sh
sh dev/tests/installer/test-updater.sh
sh -ec 'work=$(mktemp -d "$PWD/parse/output/qt-tests.XXXXXX")
trap '\''rm -rf -- "$work"'\'' EXIT
export XDG_CACHE_HOME="$work/cache" XDG_CONFIG_HOME="$work/config"
export XDG_DATA_HOME="$work/data" XDG_STATE_HOME="$work/state" TMPDIR="$work/tmp"
export QML_DISABLE_DISK_CACHE=1
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$TMPDIR"
for test in dev/tests/services/test-conflict-qt.py dev/tests/ui/test-*.py; do
    QT_QPA_PLATFORM=offscreen python "$test"
done'
```

Lint uses Qt6Qml's `qmllint` through pkg-config, checking every file independently
with zero warnings. Override `QMLLINT=/path/to/qt6/qmllint` if needed; use Qt6 tooling
rather than a legacy Qt version's executable. `make clean` removes
runtime binaries too: rebuild both helpers before launching afterward.

Installer fixtures mock downloads/systemd and build actual helpers from source-only
GitHub-layout archives. Offline pimsync uses disposable vdir stores, not a server or
real credentials. Qt probes do not launch Quickshell. Negative-case diagnostics and
the nested aggregate-test `Error 1` are intentional; the outer suite must exit 0.

Updater regression also launches a minimal **headless** Quickshell IPC fixture,
never the desktop calendar. Its short private temporary runtime avoids Unix socket
path limits and is cleaned after stopping the instance. It tests actual
CLI inventories, shutdown/reload/readiness, and later confirmation, in addition to
mocked failure/rollback/data-preservation and real native source-only builds.

For a manual isolated UI fixture:

```sh
make -C parse output/sync_group_test_helper
node dev/tests/recurrence/test-grouped-resolution.js --manual-view
```

Rebuild this generated fixture helper after cleanup or `make clean`; runtime helper
binaries alone do not provide it.

Follow printed launch/toggle commands. Check conflict Local/Remote choices and
unrelated-conflict isolation; create/edit/count/reminder round trips; timing changes,
group collapse/expand and whole-series deletion; restart persistence. Stop fixture
before cleanup. Its printed launch commands use a short private IPC/Hyprland bridge;
it does not change Hyprland configuration.
Do not provoke uncertain recovery against live data.

## Validation coverage and limits

Local checks cover native recurrence expansion, persistence, grouped transactions,
conflict protection, import/cache generation, UI interaction and layout. Installer/
updater fixtures cover source-only builds, configuration preservation, unsafe paths,
confirmation cleanup, failed-update restoration and headless Quickshell IPC.
Concurrency regressions cover broker snapshots and pending-update receipts. Desktop
checks include whole-series edits/deletion, conflicts, restart persistence and zoom.

These checks are not exhaustive. Compatibility with libical 3.x, all live CalDAV
interleavings, real OS timezone migration and power-loss/fsync-failure injection
remain unverified. Local journaling and regression results do not establish remote
atomicity.
