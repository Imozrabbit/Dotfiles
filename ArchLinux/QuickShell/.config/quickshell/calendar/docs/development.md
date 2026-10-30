# Development

## Layout

- `shell.qml`: service/window composition and `calendar.toggle` IPC.
- `common/`: event/profile validation, calendar layout and recurrence schema.
- `services/`: profile storage, range queries, persistence and conflict state.
- `services/CalendarImportService.qml`: one-time import coordination and profile
  rollback; `parse/src/import_source.cpp`: private workspaces and bounded downloads.
- `ui/`: views, editor, details and conflict review.
- `services/CalendarCalDavService.qml`: connection/settings/removal/conversion through
  the async backend coordinator. `parse/src/caldav_{config,settings,sync,removal,conversion}.cpp`:
  native discovery, owned lifecycle operations, scheduling and complete cache publication.
  `caldav_attach.cpp`: local-to-synced export, staged review, activation and cleanup.
  `caldav_remote{,_create,_review,_delete}.cpp`: bounded DAV transport, create-then-Add,
  pure preservation projection and two-file deletion coordination.
  `parse/src/removal_files.h` shares small file/process primitives with URL/local removal;
  CalDAV transactions and dependency decisions stay backend-specific.
- `CalendarConflictManager.qml` composes conflict stores by calendar. Pair names,
  calendar IDs and state paths are not interchangeable.
- `parse/src/`: C++17/libical parser, recurrence expansion, ICS serialization,
  grouped transactions and conflict resolution.
- `parse/test/` and `dev/tests/`: native, shell, Node and actual Qt regressions.

Runtime helper paths remain `parse/convert`, `parse/calendar-sync-helper` and
`parse/conflict-broker.sh`. Generated objects, test executables and disposable
fixtures belong in ignored `parse/output/`.

Native build wiring lives in `parse/Makefile`. Before running a development source checkout,
build its helpers with `make -C parse convert calendar-sync-helper`. Installed release
packages already contain these tools; clients do not compile them.

`dev/`, `parse/test/`, `parse/.clangd` and module-local `AGENTS.md` are local, Git-ignored
development files. Deployment excludes them, disposable artifacts, `docs/` and `.gitignore`;
the last two remain in Git. Clients receive prebuilt helpers and runtime/deployment
scripts, not `parse/src/`, Makefile or source tools. README links point online.
Fresh clones/client installs lack these tests; keep local test directories for
automated development checks.

## Recurrence contract

Persist logical masters, not expanded occurrences. On data/range changes,
`OccurrenceRangeStore` requests the visible range for native libical expansion.
Request IDs/signatures reject stale results. There is no renewal task or recurrence polling.

The editor offers Daily, Weekly (several weekdays), Monthly (dates or ordinal weekdays)
and Yearly (month/date pairs). **Never**, inclusive **Until**, and total **Count** (including
the first occurrence) correspond to the stored ending modes below. Editing/deletion affects
the whole series; imported exceptions or rules that cannot be edited losslessly stay read-only.

Authored rules contain exactly `frequency`, `interval`, `startsOn`, `pattern`, `ends`.
Dates below are synthetic, not calendar data.

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
  January 1. Empty initial cycles keep their phase; normalization finds the first
  occurrence without changing the rule boundary.
- Interval/count are positive integers up to 2147483647. Endings are `never`,
  inclusive `date` with an ISO date, or total `count`. Until cannot precede boundary.
- Skip nonexistent dates, absent fifth weekdays and nonexistent DST start times.
  Deduplicate before COUNT; queries do not reset the count.
- Timed series keep their creation timezone's start clock and initial elapsed
  duration; viewers display local time. Overnight initially ends next day.
  Authored All-day occupies one date with exclusive next-date end.
- Edit/delete applies to the whole series. There is no occurrence-exception editor.

Imports retain ICS and honor supported RRULE, RDATE, EXDATE, RECURRENCE-ID and
cancellations. Supplied VTIMEZONE takes precedence; floating values use the viewer's
timezone. Nominal DURATION days/weeks advance source-zone dates before elapsed
hours/minutes/seconds. RDATE periods determine duration before overlap filtering so
broad/narrow queries agree. Malformed/unsupported input warns without rewriting
source or inventing occurrences. Rules the editor cannot represent losslessly stay read-only.

Arbitrary Yearly pairs use standard per-pair ICS resources with grouping metadata,
not a cross-product RRULE. Their union determines COUNT's inclusive cutoff; logical and
member identities survive edits. Complete compatible groups collapse into one cache
master. Missing/divergent/foreign members stay visible and protected; rebuilding never
silently repairs canonical sources.

Preserve unknown ICS properties, calendar envelopes, timezone components and opaque
alarms. Compare timezone components using normalized clones, not rewritten originals.
Changing all group dates transfers common opaque content; refuse changes that would
discard unique removed-member content. Group collapse has the same lossless policy.

Standards reference: [RFC 5545 recurrence sets](https://www.rfc-editor.org/rfc/rfc5545#section-3.8.5.3).

## Safety and cost boundaries

Grouped writes require paused sync, serialization/calendar locks, all-member stale
checks and a durable local journal. Failed/interrupted resolution retains startup
guards; local rollback does not imply remote rollback. Choices cover immutable
whole-group snapshots; review every pair before applying. Clear conflicts only after
verifying canonical members and rebuilt cache. Ordinary routes cannot bypass stored
group ownership when metadata disappears.

Before/after source sets have separate 16 MiB limits including UIDs; Base64 journals
have a 64 MiB ceiling. Conflict snapshots use the same per-side budget.
`conflict_limits.h` bounds encoded state, including duplicated/nested JSON and protected
previews; the QML reader must stay compatible. Limits are not preallocations.
Validate CLI arguments and process output before state changes.

Expansion has finite work/output limits. Ancient subdaily INTERVAL>1 rules iterate
from seed because libical seeking can alter cadence; hitting the cap fails safely.
Some zoned/nominal-duration rules need conservative lookback. Do not hide these ceilings
by weakening limits or hand-writing recurrence arithmetic.

Zoom uses wheel-only MouseAreas because WheelHandler ignores synthesized
wheel input. `acceptedButtons: Qt.NoButton` leaves clicks alone; `cursorShape:
undefined` resets cursor ownership so underlying cards retain hand cursors. Reject
non-Ctrl wheel events rather than scrolling manually. Qt regressions cover native and
synthesized events and full view geometry, not just extracted callbacks.

Single-file imports keep a 2-second stability wait. Synced mutations atomically rewrite
one JSON document, replacing only affected event/member UIDs. UID/group header scans
locate resources without parsing unrelated ICS or maintaining an index. Full-cache
publication requires successful sync and strict complete staged conversion, including
scoped recovery/resolution; no edit-time full-directory fallback. Legacy unscoped
recovery CLI/guards stay compatible. Remote-named ordinary resources use a bounded
leaf-name field in v2 group journals; v1 and canonical group-member path checks remain supported.
Replace spelling-sensitive wiring tests only with equivalent behavioral coverage.
Import registry/cache commits are not a cross-file transaction. Native ICS mtimes can
advance one second beyond prior source to avoid older pimsync vdir etag misses;
cache mtimes are unaffected.

CalDAV regressions in `dev/tests/caldav/` use installed pimsync, disposable loopback DAV
and fake systemd. They cover discovery/Cancel, Add rollback/database sidecars, two-way
edits, complete-cache publication, independent timers, daemon exclusion, scoped ordinary
and group conflicts and production QML restart. HOME/XDG/TMP are private; no live credentials
or server data. Credential-bearing native jobs disable core dumps. Group callbacks have
a separate, larger virtual-address budget than URL downloads for Qt timezone initialization
and bounded conflict snapshots.
Status tests start without CalDAV state, then exercise repeated atomic busy, completion
and failure updates through the production watcher and manager Loader recreation. Test-only
reloads must not hide missing filesystem notifications. Forms scroll with hidden scrollbars;
themed tooltips keep compact dimensions and complete plain-text diagnostics. Trigger tests
check empty immediate/settled success banners, visible red failures and error clearing on retry.
Removal tests use real native staging, synthetic filesystem failures, fake systemd
properties/links/state and loopback Add. They cover full cleanup, no removal-time pimsync,
server or credential use, shared dependencies, offline/missing/malformed targets,
active/recovery refusal, ordinary rollback, late replacements and post-commit warnings. Production
QML covers Cancel/Delete, stale confirmation, neutral progress, concurrent-write guards,
re-add and empty restart. A compositor-free Qt surrogate exercises CalendarWindow's
selection/editor retirement callback; desktop smoke stays manual.
Removal-review tests also cover overlapping unmanaged/URL ownership, inline pairs,
custom-daemon prerequisites, cross-type stale confirmation and failed
conflict-selection/resolution launches. Failed Process starts retire only owned pending state on a deferred
check with both workers idle, never clearing active operations or bypassing recovery guards.

`dev/tests/services/test-optional-file-warnings-qs.py` tests production services from
an empty registry without optional holiday/config/status/conflict files. It covers quiet
absence without placeholders, first creation/atomic replacement, imported/conflict updates
without test-only reloads, malformed data, lost known conflicts and selective nonmissing
I/O diagnostics. Permission-denial cases reload explicitly and skip root; they do not
verify watch registration. CalDAV Add/remove/re-add panels also check quiet expected absence.
The imported reader must reload on `fileChanged`; `watchChanges` only emits the signal.
Keep logging selective per FileView, not globally filtered.

Synced-to-local conversion reuses the coordinator and conflict previews. Public actions
are `convert-begin`, `convert-finish`, `convert-cancel`; CalDAV listing includes retained
sessions. Choices stay in service memory across Loader reopening; shell restart restores
the native pause but may require new choices. No per-choice native writes, polling or
second controller. The final command keeps an independent local result, then runs read-only
all-pair preflight, batch conflict application and one real pimsync settlement sync.
Owned callbacks do not reacquire the parent's lease. Retirement has narrow check-only and
keep-local paths; ordinary Remove never synchronizes.
Local JSON v3 keeps strict `ical`/`readOnly` metadata and logical recurrence, dropping
sync-only `sourceUid`, `revision`, `seriesGroup`. One unambiguous simple all-day `-P1D`
displays as 1440 minutes; original alarm/order survive edits, and its snapshot participates
in stale revisions. Staged conversion checks source digests/cache records and retains the
complete single-event resource read-only; ambiguous shared resources fail before final sync.
Nominal and elapsed one-day triggers stay distinct; other civil/recurring/ambiguous alarms
stay opaque. Synthetic parser, native mutation, conflict-choice and attachment round-trip
fixtures cover both DST transitions and alarm preservation/removal.
`test-local-conversion.js` covers codec round trips. Native `test-conversion.py` covers
three-way choices, grouped local-only, ETag races, pause/Cancel, staleness, pending/empty
calendars, dependencies and complete retained-path warnings. Review tests require complete
source/cache correspondence before network work, validate native output with the production
local reader, preserve late source/destination/link replacements and keep modified Cancel
copies. Strict private reconstruction is compared with published cache, never republishing
unreviewed partial downloads. Unexpected post-settlement sources retain conservative
collection staging rather than becoming purge targets. Bounded ScrollView recovery messages
are tested by scrolling the last path into ancestor-visible bounds.
`test-conversion-panel.py` covers production Loaders/services, pause/local restarts,
revisiting choices, Cancel, mutation guards, final confirmation, editor retirement,
rendering/read-only persistence, network failure and missing executable. QtTest pointer
and key events select version cards, the conversion-only keep-local card and Confirm through
the coordinator. Checks cover both local-only highlights, repeated top-card selection,
plain-local/remote clearing, no staging/network before Confirm, restored choices, discarded
drafts and compact footer. The ordinary Qt probe covers card pointer/keyboard selection,
reviewed snapshots and Confirm routing so conversion cannot redirect ordinary resolution.
Manager geometry checks blue border/fill only on the active conversion target, unmatched-ID
fallback and cleared sessions. Production flow checks highlights after native pause/restart,
before confirmation, and removal after Cancel/success. Native `Qt.alpha` handles theme strings.
Pointer/Return events begin review through opposing arrows, then inline **Convert to local**.
Geometry checks dimensions/dimming, anchored tooltips even with the action row disabled,
and locked-action hints. The Qt surface surrogate uses CalendarWindow's NavButton, toolbar,
Loaders and panels: gear opens manager and shows conflicts in amber; normal footer opens
ordinary review; manager reopens after either panel closes or paused conversion restarts.
Tests use production navigation, not substitute wiring.
Conversion/removal categories use one panel-local calendar ID/category. Same-icon activation
collapses; another card/category replaces it; selecting a leaf/form or starting work clears
expansion. Collapsed cards reserve no action line. Categories need no backend/service
changes or menu framework.
Geometry tests cover keyboard/pointer toggles, one-open behavior, attachment leaf routing,
compact/full containment and no work on expansion. Missing-remote warnings persist with
Keep local/Delete local in their categories. Lifecycle fixtures select an action after
expansion; multi-calendar probes scope duplicate icon names to the target card.
Conversion uses a centered 16×16 Canvas in the 28×28 button, not a font/cloud glyph.
Shared icon color preserves hover/dimming. Qt checks opposing-arrow pixels and ink/box
centering for both profile types and compact/full widths, mapping window grabs to nested
icons with actual device pixel ratio, including `QT_SCALE_FACTOR=1.5`.
The Qt conflict probe checks gear amber state, Tab focus, Space/Return/Enter activation
and full accessible unresolved count above 99. At zero, gear stays visible without warning
color; no separate badge. Manager QtTest geometry/status checks footer activation,
compact/full count placement, hovered-option tooltip anchoring and above fallback. It
catches hidden footer actions retaining focus after form/deletion navigation and checks
default blue primary buttons, conflict arrival/resolution, disabled/dimmed actions, already-open
Save, direct handler guards, unaffected calendars and full failure details. Production
conversion guards reject Refresh/settings before launch while keeping conversion available.
Conversion panel cases run in `make -C parse test`; the Qt conflict probe uses the isolated
checks below. Physical desktop conversion stays manual.

## Remote calendar lifecycle

Qt6Network handles same-origin principal/home discovery, complete read-only snapshots,
`MKCALENDAR` and exact collection DELETE. Credentials stay in the private file; never
forward them through redirects, disable TLS validation or add a product test-CA option.
Discovery/snapshot passes have 30/90-second limits. Each network/local event side and
final local JSON is capped at 64 MiB; individual ICS at 16 MiB, review payload at 616 MiB,
compact operation metadata at 1 MiB, control JSON at 64 KiB. Both final-choice actions
accept up to 64 MiB of choices. Refuse excess; never truncate.

`caldav create` validates local identity/profile/config revision before creation, verifies
the target, then delegates Add. Confirmed partial creation permits Add-only retry; unknown
creation never automatically adopts or repeats MKCALENDAR.
`remote-delete-begin/finish/cancel/retry` share the conversions listing/coordinator with
`kind: 'remote-delete'`. DELETE requires current `phase: 'review'` and an explicit final
request. Local/remote-only choices are offline and session/revision-bound; changed review
revision clears them. Three-choice conversion stays separate. Permission-filterable `404`
plus home omission means Unknown. Read-only `410 Gone` requires a complete response,
accessible expected home and omitted target; otherwise retain the operation. Lost DELETE
replies on 404-only servers need manual inspection, not automatic success or another DELETE.

Pure preservation uses existing parsing/group/revision/serialization codecs and shared
`makeLocalDocument`; review/projection has no I/O. Validate whole sides, not differing group
member sets forced through paired-only conflict capture. Reject unknown non-event components;
keep opaque event/recurrence properties and alarms in read-only ICS. Compare complete
normalized sources with native model output, excluding only sync bookkeeping—not just
reminder counts or recurrence signatures. Refuse groups whose extra opaque data cannot fit
local logical recurrence; do not change group storage or legacy conversion. Reject cross-side
member UIDs with different logical identities. Validate merged serializer warnings/logical-event
count before local projection. Before deletion, compare canonical sources with displayed
cache; never conceal divergence by rebuilding/publishing partial caches.

Deletion uses one payload and one compact record, not a conversion snapshot tree. Persist
pending/current payload digests across atomic publication. Low-level guards cover sync,
mutation, ordinary/group conflict selection and group recovery even with malformed/missing
markers. Successful deletion uses shared removal inventory/rendering in capture-only mode
and a separate finish-forward executor, never legacy rollback/staging or upload-capable
final sync. Record stage inode/digest before create-only local publication so restart
recognizes moved payloads. Preserve unrelated concurrent config/profile edits and newer
local events. Final retirement preflight rechecks destination absence before DELETE.
Shared QML persistence checks lifecycle guards, including move source before destination
publication, so publishing the profile before its activation checkpoint cannot permit edits.

`test-remote-transport.py`, `test-remote-create.py`, `test-remote-review.py`,
`test-remote-delete.py [prepare|finish|all]` and
`test-remote-lifecycle-panel.py [create|delete|all]` run from the normal test target.
The bridge links production objects; only tests inject a private CA. Fixtures cover
empty accounts, create races/uncertainty/Add-only retry, identity unions/group asymmetry,
fidelity/limits, exact Cancel/scheduling, two-file guards/checkpoints, unchanged CTag,
lost/partial/async/masked responses, death after DELETE/publication, activation/cleanup
failure and unrelated/newer data preservation. QtTest uses production CalendarWindow
Loader/panel routing and pointer/keyboard events for zero-conflict reconfirmation,
restarts, unrelated Remove confirmation isolation and guarded local
create/update/delete/persist/moves between profile publication and checkpoint. Physical
server capabilities/permissions and desktop lifecycle remain unverified until separately
authorized disposable tests.

### Local-to-synced attachment

`attach-begin/finish/cancel/retry` use the async coordinator and conversions list with
kind `local-to-synced`. The manager form's attachment mode fixes profile metadata and
uses read-only discovery. Its remote picker also offers creation. `syncedConnection()`
adds `createRemote`, `homeHref`, `remoteName`, `collectionId` to the attachment request;
no new service method or coordinator is needed. Native preflight precedes
`createRemoteCollection()`, then ordinary review/activation/sync resumes. Creation failures leave the form open;
known-created targets permit existing-target retry, uncertain creation invalidates discovery.
Created collections are never rollback/cleanup DELETE targets. New-profile Create and add
stays separate and unchanged. The conflict panel offers only Local/Remote; service-level
one-shot progression submits when choices cover the current revision. Refreshed choices
survive adoption only with matching event UID/revision. Pending attachment guards cover
profile-store writes, initialization and higher-level mutations.

The coordinator validates local JSON→ICS→cache fidelity with existing codecs, preserving
opaque resources. Shared `projectRemoteSources()` selects complete resources/series; the
old preservation JSON projection composes it without weakening comparisons/revisions.
The editor also saves timed one-off timezones. Native JSON/ICS/cache/conflict code preserves
validated `X-QUICKSHELL-TIMEZONE` with standard UTC DTSTART/DTEND, including second DST-fold
instants. One-off zone changes affect revisions; merging replaces old hints without
duplicates. Invalid, duplicate or parameterized hints keep original ICS read-only. Zone
metadata uses cache version 3; no new schema/migration. Different timestamp spellings must
represent equal start/end instants. Nonzero raw fractional digits, including submilliseconds
Qt would round, fail native authoring and opaque-wrapper attachment before writes.
Invalid zones fail; other fields keep exact checks.
Final preparation runs pimsync with `read_only` remote storage in private staging. Portable
pair DB/history moves with canonical resources; ordinary writable sync handles reviewed
overwrites/additions/member deletions without another callback protocol. Reuse the monotonic
ICS writer: second-resolution vdir etags otherwise miss same-second local winner updates.

Persist `syncAttempted` before worker launch. Synchronous read-only preflight or executable-start
failure may clear it and roll back only without an earlier writable attempt. Process death
leaves a conservative durable boundary; Retry never resets it. Returned sync errors retain
active sources/cache/history and ordinary conflicts. After dependency-aware cleanup, ordinary
Refresh owns retry. Incomplete activation/cleanup retains the session and reports recovery
paths. Never infer server rollback.

`test-local-to-synced.py [export|prepare|activate|safety|create|timezone|nominal|all]` and
`test-local-to-synced-panel.py [union|conflicts|cancel|refresh|recover|failure|create|create-empty|create-retry|create-uncertain|create-timezone ...]` run through
`make -C parse test` with real helpers/pimsync, private loopback DAV and fake systemd.
Coverage includes empty/populated unions, UID prefix/collision refusal, exact opaque ICS,
asymmetric whole-series winners, retained choices, stale local data, exact pre-sync rollback,
interrupted-sync boundary, ordinary post-error/cleanup-only retries and unrelated/shared
resources/history. Production QML covers pointer/keyboard chooser/review, automatic progression,
restart adoption, direct-store guards and result messages. Creation tests cover empty accounts,
native preflight before mutation, existing/concurrent collisions, metadata/local-file preservation,
Cancel without remote deletion, uncertain responses, post-create snapshot failure and attachment-only
retry with exactly one MKCALENDAR. Panels click the password-file button/popup/file rather than
injecting credentials. Timezone tests pair a UI-style one-off (`Europe/Paris`, `.000Z`, reminder)
with a three-count daily series. They cover existing/create-target attachment, conversion back
to local, production create-timezone UI, direct codec/update/stale revision, DST folds and invalid
metadata/precision safeguards. Private saved-baseline probes stay in ignored output; tracked
tests use synthetic identities/descriptions. Choices use the 64 MiB finish bound; bounded
recovery inventories must stay listable/cancellable. Cleanup checkpoints keep a stable
conflicts-array interface after staging deletion. Pre-sync `discarding` permits cleanup-only
Retry after interrupted Cancel without deleted review/activation files. Tests use no live
credentials/collections and never change user services.

## Checks

Build dependencies: C++17 compiler, Make, pkg-config, libical, Qt6Core and Qt6Network
(both from `qt6-base`). Tests add Node.js, jq, pimsync and usual POSIX tools; Qt probes
add Python/PySide6 and QtTest QML. Run from this config with private HOME/all XDG/TMP
set before Qt. Use ignored output or approved `/tmp/opencode`, disable QML disk cache
and stop fixtures before inspected cleanup, including after failures:

```sh
make -C parse test
make -C parse lint
python dev/tests/services/test-optional-file-warnings-qs.py
python dev/tests/services/test-import-qs.py
sh dev/tests/installer/test-installer.sh
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

The native import-session test runs in `make -C parse test`, using Python/OpenSSL private
HTTP/HTTPS feeds for certificate/redirect safety, gzip, size bounds, token privacy and
orphan/active-job cleanup. Headless Quickshell tests use private XDG/TMP/IPC and production
UI/services for managed single-file import, source-byte preservation, original consumption,
read-only/instant events, week-card/month-bucket visibility, failed helper starts,
missing/invalid/FIFO sources, Cancel/Delete, re-add and restart. Native tests cover valid
empty/optional data, whole-import failure, occupied destinations, import/removal write-failure
rollback, original-deletion warnings and private modes under umask 0022.
`test-local-ics-races.py` compiles a disposable LD_PRELOAD boundary shim for
original/snapshot/rollback races, linked collections and invalid override identities,
without production hooks.
The registry skips unchanged metadata writes without waiting for FileView saved signals.
These fixtures never access live calendars.

### Reminder delivery

`shell.qml` keeps `ReminderService` alive while this Quickshell config runs, including
with its window/calendars hidden. It supports local, imported ICS, subscription and
synced reminders. Installed `notify-send` (`libnotify`) sends notifications through a
user-session notification server. No independent daemon or extra package is added.

`ReminderSchedule.js` builds unique occurrence/lead/deadline keys and keeps a process-lifetime
high-water clock. Startup skips elapsed deadlines; timer gaps over five seconds skip missed
alerts, including after wake. Backward clock changes never replay deadlines; failed/uncertain
sends are not retried. Ordinary events and native recurring/retained-ICS occurrences are
scheduled one hour ahead, refreshed every half hour and on source changes. Unchanged
sources keep valid queued deadlines during native queries; stale results are discarded.

Native `expand` accepts optional `forReminders: true`: ranges bound alarm deadlines,
not visible events. Lookahead includes supported override alarms; alarm-free overrides
never inherit master alarms. Silent series skip expansion. Native work/output limits
remain: dense series with long leads may fail the query rather than deliver reminders.
Rich/absolute/end-related/email/audio alarms stay opaque; no new ICS alarm model or
upstream duration/DST fix is introduced. Helper/sender failures appear in `errorMessage`
and Quickshell output, never as successful delivery.

`make -C parse test` discovers `dev/tests/reminders/test-reminder-schedule.js` and
runs `test-reminder-native.py` and `test-reminder-qs.py`. The QML fixture uses
real stores, native recurrence and Process launches with private HOME/XDG/TMP/IPC,
fake clock/sender and inaccessible notification D-Bus. No live events or desktop
notifications. Personal smoke stays a separate user-operated check.

The picker keeps raw local filenames. Folder URLs use Linux `//proc/self/root/` to avoid
FolderListModel reparsing decoded paths, including special characters in the first
component. Remove this workaround when Qt fixes `QQuickFolderListModelPrivate::resolvePath`.
Returned paths strip the alias and normalize to one leading slash; no files are copied or
stored under `/proc`. No custom scanner or dependency is needed. CalDAV reuses the popup
with all-file filtering and its own selector anchor, writing only the password-file
reference. Local ICS selection filters `*.ics` and writes only its source path. Production
panels test both targets, Cancel, hidden/extensionless credentials, special-character
directories, discovery invalidation and unchanged credential bytes/modes.

Lint uses Qt6Qml's `qmllint` through pkg-config, checking each file independently with
zero warnings. Override `QMLLINT=/path/to/qt6/qmllint` if needed; use Qt6, not legacy
tooling. `make clean` also removes runtime binaries; rebuild both helpers before launch.

Installer fixtures validate runtime archives with real files/Git and mocked network and
systemd; native builds stay in development-PC staging, never clients. Offline pimsync
uses disposable vdir stores, no server or real credentials. Qt probes do not launch
Quickshell. Negative diagnostics and nested aggregate-test `Error 1` are intentional;
the outer suite must exit 0.

Updater tests launch a minimal **headless** Quickshell IPC fixture, never desktop Calendar.
A short private runtime avoids Unix socket path limits and is cleaned after shutdown.
It tests real CLI inventories, shutdown/reload/readiness and confirmation, alongside
mocked failure/rollback/data-preservation and private native deployment checks.

For a manual isolated UI fixture:

```sh
make -C parse output/sync_group_test_helper
node dev/tests/recurrence/test-grouped-resolution.js --manual-view
```

Rebuild the fixture helper after cleanup or `make clean`; runtime helpers do not provide it.

Follow printed launch/toggle commands. Check Local/Remote choices, unrelated-conflict
isolation, create/edit/count/reminder round trips, timing changes, group collapse/expand,
whole-series deletion and restart persistence. Stop the fixture before cleanup. Launch
uses a short private IPC/Hyprland bridge without changing Hyprland configuration.
Never provoke uncertain recovery against live data.

## Validation coverage and limits

Local checks cover native recurrence, persistence, grouped transactions, conflict
protection, import/cache generation, UI interaction and layout. Installer/updater fixtures
cover runtime-only releases, configuration preservation, unsafe paths, confirmation cleanup,
failed-update restoration and headless IPC. Concurrency tests cover broker snapshots and
pending-update receipts. Desktop checks include whole-series edits/deletion, conflicts,
restart persistence and zoom.

Coverage is not exhaustive. Libical 3.x compatibility, all live CalDAV interleavings,
real OS timezone migration and power-loss/fsync-failure injection remain unverified.
Local journals and regressions do not establish remote atomicity.

## Local runtime release packaging

From the Calendar source root:

```sh
python3 -I -B tools/package-release.py
```

The development-only packager reads `VERSION` (currently `0.1`) and the explicit
`release-files.txt` allowlist. It freezes owned, unlinked inputs in private staging,
builds `convert` and `calendar-sync-helper` with the Makefile, checks ELF architecture,
and packages runtime files under one `calendar/` root. It never replaces working
helpers/objects, runs the installed application, installs packages, changes services,
accesses calendars/credentials, contacts servers, commits, pushes or publishes.

Requirements on the development PC: Linux x86_64, Python 3.11+, Make, g++,
binutils/readelf, pkg-config, libical and Qt6Core/Qt6Network development files.
Builds use default Makefile compiler settings without inherited make/compiler overrides.
HOME, all XDG paths and TMPDIR are private before builds start. Cancellation kills the
owned build process group before deleting staging.

Each successful invocation creates a new private, Git-ignored directory:

```text
dist/releases/calendar-v0.1-linux-x86_64-<unique-id>/
  calendar-v0.1-linux-x86_64.tar.gz
  calendar-v0.1-linux-x86_64.tar.gz.sha256
```

`dist/` is Git-ignored. Whole-app archives go in `dist/releases/`, separate from native
`parse/output/`. Same-code private update fixtures go in `dist/fixtures/` with an external
`DO-NOT-PUBLISH.txt`, never release tags/assets. Remove superseded candidates/fixtures
after replacement verification. Historical `parse/output/` archives were retired, not
build inputs; never restore or publish old source-building installers from backups.

Earlier candidates are never overwritten. Handled failures/cancellation clean staging
without leaving a completed archive/checksum pair. Packager SIGKILL or power loss may
leave staging for inspected cleanup. From the candidate directory, run
`sha256sum -c calendar-v0.1-linux-x86_64.tar.gz.sha256`; checksums detect corruption,
not publisher authenticity.

The archive contains version/runtime manifest, QML/JavaScript, Python/shell deployment
files, conflict broker and fresh helpers. It excludes the packager, native source/Makefile,
`tools/`, tests, developer docs/tooling, build output, logs, caches, event stores and
credentials. Review new runtime QML/JS and explicitly add it to `release-files.txt`.
Unexpected files, links, unsafe paths or changed input snapshots stop packaging.
Packager and client share `deployment/release_archive.py`'s format policy. Before publishing
a local candidate directory, the packager validates/extracts the archive privately with
the client reader, then discards that extraction.

Archive owners, permissions and timestamps are normalized; native binaries are not
guaranteed bit-for-bit reproducible across toolchains. Dependencies remain system
libraries; `linux-x86_64` does not imply general Linux/distro portability. Current builds
require `libical.so.4.0`, Qt `6.12` symbols, `GLIBC_2.38`, `GLIBCXX_3.4.32` and usual
supporting libraries. Build-host library changes may alter requirements. Package/symbol
metadata does not replace manual client testing. Beta.1 passed user-operated ThinkPad
install/update/rollback with one local calendar. Stable `0.1` promotion can reuse that
evidence only if every runtime file, including fresh helpers, matches except `VERSION`.
Runtime or library/ABI changes require compatibility reassessment. Cleanup moved deployment
internals into `deployment/` and removed legacy setup/migration scripts and the update
alias—not a version-only change. The 39-file archive needs new extracted-entrypoint,
real artifact lifecycle and appropriate manual desktop/client checks. Cleanup preserves
native helper paths and QML/native feature behavior.

**Tagging/publication and client installation need separate manual approvals.**
A local stable `0.1` archive is not a GitHub release. When approved, use tag
`calendar-v0.1`, title **v0.1**, and **Pre-release unchecked**. Beta parsing and explicit
`--archive` remain supported. Older packaging-only candidates contain source-building
scripts; never install/publish them. Rebuild with the current runtime installer/backend
and verify. Client evidence must match that runtime, except version-only promotions
as described above. Native source/tests stay on the development PC; no tests enter
Git or client installations.

Fast local packaging regression:

```sh
python3 -I -B dev/tests/installer/test-release-package.py
```

It compiles a tiny fixture privately and checks exact membership, checksum, normalized
metadata/modes, fresh helpers, unchanged live inputs, multiple candidates, unsafe/missing
input rejection, build failure and cancelled-child cleanup. It never launches Calendar or
contacts servers.

## Runtime release deployment checks

`install.sh` and `update.sh` execute `deployment/deploy.py` under Python `-I -B`.
Bootstrap requires a trusted extracted release; no entrypoint fetches/executes `master`
scripts. `deployment/release_archive.py` discovers stable Calendar tags with bounded
pagination, enforces HTTPS redirect hosts/download limits, verifies exact checksum/name
and manifest, rejects unsafe/duplicate/linked/special members, then manually writes validated
runtime files. The format supports Linux x86_64, flat `common/`, `services/`, `ui/` and
explicit root/deployment/helper files. Unsupported versions/layouts stop deployment;
validation is never relaxed.

Versions use numeric `major.minor[.patch]` and optional `-beta.N`, without leading zeroes.
Ordering compares numeric base, beta/stable rank, then numeric beta index:
`0.1.0-beta.2 < 0.1.0-beta.10 < 0.1`. `0.1` and `0.1.0` compare equal; do not publish both.
Alpha/RC/build metadata and automatic beta channels are unsupported. Discovery excludes
beta suffixes regardless of GitHub's prerelease flag; manual beta install/update uses
`--archive PATH`. Downgrade protection includes stable `0.1` → same-base beta.

Clients never invoke compilers. Before activation, the compatibility probe converts
synthetic ICS and expands one occurrence with private HOME/all XDG/TMP. Missing packages,
including pimsync and notify-send, require pacman consent. The initial registry is empty;
no legacy source setup or pimsync localization/tracking migration runs.

Native read-only interfaces:

```sh
parse/calendar-sync-helper deployment-plan
parse/calendar-sync-helper deployment-verify
```

Both return `{ok,schema:1,dataSchema:1,files,units}` using profile/config
parsers and URL/CalDAV `unitDefinitions()`. `files` maps relative unit names to text;
`units` lists the managed runtime daemon/watchers/timers/instances. They do not
write units/state, read credential contents or contact servers.
`deployment-verify` additionally checks the effective recovery guard and managed
CalDAV daemon routing. The deployer owns the persistent shared lease; export never uses or
inherits the mutating `subscriptions units --locked` fd-9 interface. Release builds did
not replace working development helpers; use an extracted release helper or fresh private
build for these commands.

The installer records complete application hashes/modes/ownership and routing in owned
`installer/installed.json`. Updates use directory flock and shared `calendar-pimsync.lock`,
preserving its inode and never unlinking it. Before pausing, it checks owned unit text/metadata,
effective routing, recovery, configuration, Git exclusion and selected-path Quickshell inventory.
Fsynced `installer/pending.json` binds old/new inventories, owned unit snapshots and
same-filesystem rollback paths. Uncertain failures retain journal/rollback; manual rollback
never restores data. Confirmation deletes only verified old code, including unchanged
remainders of interrupted approved cleanup. See the [installation guide](installation.md#update)
for client update/confirmation/rollback commands.

Local checks (all remain Git-ignored):

```sh
python3 -I -B dev/tests/installer/test-release-archive.py
python3 -I -B dev/tests/installer/test-release-deploy.py
python3 -I -B dev/tests/installer/test-release-entrypoints.py
python3 -I -B dev/tests/installer/test-deployment-native.py /path/to/privately/built/calendar-sync-helper
python3 -I -B dev/tests/installer/test-release-runtime-qs.py
python3 -I -B dev/tests/installer/test-release-artifact.py /absolute/path/calendar-v0.1-linux-x86_64.tar.gz
```

Archive tests use real filesystem/tar inputs, stubbing only network. Deployment tests
use real files/Git with mocked system/native orchestration. Native tests exercise real
empty/URL/CalDAV/mixed templates; headless Quickshell tests exercise selected-path inventories
and IPC in a short private `/tmp/opencode` namespace. The synthetic shell is not Calendar
and stops before cleanup. Use UTF-8, such as `LC_ALL=C.UTF-8`, not `LC_ALL=C`: Qt's locale
warning contaminates Quickshell stdout JSON/IPC. Installer/updater shell entrypoints invoke
release checks. Obsolete source-build fixtures, one-off client remover and legacy
setup/localization-only tests were deleted. Installation starts empty; UI/native operations manage
sources. These tests include no notification probes, live client installs or publication.
Isolated checks do not replace client/systemd/library verification; identical-runtime version
promotions may reuse evidence as above.

The artifact test uses real release/backend/native helpers for isolated install →
higher-version same-code update → rollback → update/confirmation. Its process gate allows
only private native probes/plans and selected-path Quickshell listing—no services, GUI,
packages, notifications or server commands. Only package-presence checks are bypassed,
covered separately by dependency-consent fixtures. Checks include data hashes,
ownership/modes/inodes/timestamps and persistent lock inode. Synthetic higher-beta archives are labeled,
disposable and never published. Beta baselines increment only beta index; stable baselines
use next patch's beta.1, never a synthetic stable-looking version.
