# Calendar audit

Calendar shows a university timetable alongside local, imported, and synced events in week, month, and agenda views. Local events stay on disk; synced events use ICS files and a rebuildable JSON cache. Conflicts ask you to choose a complete Local or Remote version.

## Audit at a glance

- **Correctness and data integrity:** Traced event editing, ICS conversion, migration, cache writes, and conflict resolution. Confirmed defects received regression tests and fixes.
- **Security and resilience:** Checked malformed input, permissions, stale conflict choices, plain-text rendering, and atomic writes. Fixed confirmed unsafe behavior.
- **Performance and complexity:** Removed redundant process work and skipped unchanged converter output. Kept the 2-second import stability wait and full synced-cache rebuild by user choice.
- **Tests and maintenance:** Clean build, native/shell/Node tests, QML lint, and an isolated IPC smoke test passed. Source-text wiring assertions remain pending separate test cleanup.

Detailed findings follow for maintenance and future review.

**Status:** Full audit and short second pass complete. Active calendar QML, JavaScript, native helpers, process coordination, runtime overhead, and tests reviewed. Confirmed defects were fixed with regression tests; user-selected overhead and test cleanup remain deferred. `install.sh` remains outside scope.

**Worktree:** Contains extensive pre-existing tracked and untracked calendar work. Do not reset or commit unrelated changes. Pre-audit snapshot `.audit-20260923.tar` was SHA-256 verified (`0b6c231118330deea0fd21dc3b8deda21ba20ff93c7d865146f945a43c3c7357`) and removed after final checks.

## Confirmed correctness fixes

### 1. Missing synced ICS accepted as successful deletion — fixed

- **Location:** `parse/sync_main.cpp`, `mutate()`; `parse/test/sync_helper_test.sh`.
- **Cause:** Stale revision was checked only when `fs::exists(eventPath)` returned true. `fs::remove()` returning false with no filesystem error was treated as successful deletion; helper then rebuilt cache and reported success.
- **Impact:** A deletion racing external removal silently appeared successful; source/cache divergence was hidden rather than reported.
- **Fix:** Reject missing event before update/delete; treat `fs::remove() == false` as failure. Report `fs::exists()` filesystem errors rather than treating them as absence.
- **Verification:** Regression deletes the ICS file after cache creation, then submits delete with cached revision. It failed before fix, passed after fix, and cache hash remains unchanged. `make -C parse test`, `qmllint`, shell syntax, and `git diff --check` passed.

### 2. Native helper accepted reversed event ranges — fixed

- **Location:** `parse/sync_main.cpp`, `eventFromJson()`; `parse/test/sync_helper_test.sh`.
- **Cause:** Helper checked timestamp/date validity but not `end > start`, although QML validated that condition. Direct helper requests and migration could write invalid canonical ICS; cache rebuild subsequently omitted the malformed event while reporting success.
- **Fix:** Parse dates once and require strictly increasing date/time, comparing instants for timed events and dates for all-day events.
- **Verification:** Reversed timed and all-day create requests now fail without creating ICS or changing cache. Full aggregate tests passed.

### 3. Native helper silently defaulted missing and mistyped event fields — fixed

- **Location:** `parse/sync_main.cpp`, `eventFromJson()`; `parse/test/sync_helper_test.sh`.
- **Cause:** `QJsonValue::toString()`, `toBool()`, and `toArray()` silently returned empty defaults for missing or wrong-type values. Direct helper writes and migration could turn absent `title`, `allDay`, or `reminders` into empty values and then commit ICS.
- **Fix:** Require strings for UID/title/description/location/start/end, boolean all-day flag, and array reminders before conversion. Existing QML and local JSON producer already supply these types.
- **Verification:** Missing and string-valued reminder lists now fail before canonical ICS/cache writes. Full aggregate tests and static checks passed.

### 4. Malformed conflict state unlocked synced edits — fixed

- **Location:** `services/CalendarConflictService.qml`, `loadState()`/`stateFile`; `services/CalendarService.qml`, `syncedMutation()`.
- **Cause:** Parsing an invalid conflict-state file cleared `conflicts` to `[]`, so `isConflicted()` returned false for previously known conflict UIDs. The edit path did not check whether conflict state was valid.
- **Fix:** Keep last known conflicts, track `stateValid`, and reject synced mutations while conflict state is unavailable or invalid. A missing state file with no known conflicts remains valid empty state. Other read failures retain prior conflicts and report an error.
- **Verification:** `dev/tests/test-conflict-state.js` verifies invalid state retains a known UID and blocks synced create. Red before fix, green after fix. Full Node/C++/shell suite and QML lint passed.

### 5. Redundant registry directory processes — simplified with approval

- **Location:** `services/ProfileRegistryStore.qml`, `Component.onCompleted` and `directoryProcess`; `dev/tests/test-profile-wiring.js`, `dev/tests/test-directory-permissions.js`.
- **Finding:** Startup spawned `mkdir -p` and then `chmod 700` as two subprocesses, with a second process object, failure branch, and extra readiness transition.
- **Decision:** User approved simplification during audit.
- **Change:** Replace both with one `install -d -m 700 -- <directory>` process. Keep the existing `directoryReady` gate and protective failure state.
- **Verification:** New and existing directories both end with mode `0700` in runnable test. Profile wiring, QML lint, and aggregate suite pass.

### 6. Agenda omitted ongoing and multi-day events — fixed

- **Location:** `common/CalendarMath.js`, `buildAgendaDays()`; `ui/AgendaView.qml` consumes result; `dev/tests/test-calendar-math.js`.
- **Cause:** Days were indexed only by an event's start date. Events started before the 14-day range or continuing beyond their first day never appeared on later days, unlike Week and Month views.
- **Fix:** For each valid event, add it to every overlapping day in the 14-day UI range. Compare `[start, end)` intervals so all-day events ending at midnight do not spill into the next day. Precompute day ends once.
- **Verification:** Regression covers an event beginning before the range, three-day all-day event, and exclusive end; red before fix, green after. Full aggregate tests and QML lint pass.

### 7. Inherited JavaScript property bypassed calendar visibility — fixed

- **Location:** `common/CalendarMath.js`, `filterEventsInRange()`; `dev/tests/test-calendar-math.js`.
- **Cause:** `calendarById = {}` inherited `constructor` from `Object.prototype`. Profile IDs may legally equal `constructor`, so map assignment was skipped and event lookup returned inherited function with no `visible: false`. A hidden calendar's events could display.
- **Fix:** Build lookup with `Object.create(null)`.
- **Verification:** `constructor` profile hidden-event case failed before fix and passes after. Aggregate tests and QML lint passed.

### 8. Synced event edit discarded calendar-level ICS data — fixed

- **Location:** `parse/helper.cpp`, `writeEventFilePreserving()`; `parse/test/parser_tests.cpp`.
- **Cause:** Edit serialized a new `VCALENDAR` and only reinserted unknown properties from inside `VEVENT`. Existing `PRODID`, `X-WR-CALNAME`, `VTIMEZONE`, and metadata after `VEVENT` were silently discarded.
- **Fix:** Replace only the single original `VEVENT` block with the edited block and preserved unknown VEVENT properties. Keep original calendar prefix and suffix verbatim; fail without write when original VEVENT boundaries are unavailable.
- **Verification:** New parser test asserts calendar metadata before and after VEVENT and `VTIMEZONE` survive update, then reparses edited event. Red before fix, green after. Parser, sync-helper, aggregate, and static checks pass.

### 9. Duplicate native include — removed with approval

- **Location:** `parse/main.cpp`, duplicate `<unistd.h>` includes.
- **Decision:** User approved immediate cleanup; removed second include. Converter builds and integration tests pass.

### 10. Conflict selection leaked into next conflict — fixed

- **Location:** `ui/ConflictResolutionPanel.qml`, `onConflictsChanged()`; `dev/tests/test-conflict-state.js`.
- **Cause:** After resolving the first conflict of several, `hasConflict` remained true, so the panel neither closed nor reset `selectedSide`. Next conflict appeared preselected with the previous Local/Remote choice and enabled Confirm.
- **Fix:** Track currently displayed conflict UID. When UID changes, clear selected side and pending confirmation; retain selection when the same conflict's state updates.
- **Verification:** Regression reproduces first-to-next conflict transition and same-UID refresh, failing before the fix and passing afterward. Full aggregate suite and QML lint pass.

### 11. Duplicate registry readiness flags — simplified with approval

- **Location:** `services/ProfileRegistryStore.qml`, `ready`/`editable`; `dev/tests/test-profile-wiring.js`.
- **Finding:** Both flags were initialized false, set true on successful load/default initialization, and set false on protection failures. Only the registry's `applyResult()` read `editable`.
- **Decision:** User approved removing duplicate state.
- **Change:** Remove `editable` and use `ready` to gate mutations. Keep initialization path writing defaults before `ready` becomes true.
- **Verification:** Functional test for blocked-before-ready/accepted-after-ready mutation failed before change, passed after. Profile and aggregate suites pass.

### 12. Conflict apply rewrote both versions and could partially replace data — fixed

- **Location:** `parse/sync_main.cpp`, `applyConflict()`; `parse/test/sync_helper_test.sh`.
- **Cause:** After choosing Local or Remote, helper rewrote both files in order. Winning side already held selected raw ICS, so second write was redundant; if that write failed, losing side had already changed while callback might recapture altered sources.
- **Fix:** Verify current raw files still equal captured conflict versions; reject stale choices without writing. Atomically replace only losing side with selected raw ICS. No two-file partial commit remains.
- **Verification:** Local and Remote selections succeed even when unchanged winning file is read-only. Mutation of captured winning ICS before application is rejected without changing either side. Tests failed before fix and pass after; full suite and static checks pass.

### 13. Same-UID recapture retained stale conflict selection — fixed

- **Location:** `ui/ConflictResolutionPanel.qml`, `onConflictsChanged()`; `dev/tests/test-conflict-state.js`.
- **Cause:** UID-only selection reset did not detect an updated local/remote ICS version of the same conflict. After remote `412` or another recapture, previous Local/Remote choice remained visually selected and Confirm stayed enabled against changed data.
- **Fix:** Track last displayed raw Local and Remote ICS alongside UID. Clear choice and pending confirmation when either version changes; preserve choice on metadata-only updates.
- **Verification:** Regression checks same-UID unchanged refresh retains choice, changed-version refresh clears it. Red before fix, green after; full suite and QML lint pass.

### 14. Broker retained approved choice after conflict sources changed — fixed

- **Location:** `parse/sync_main.cpp`, `captureConflict()`; `parse/test/sync_helper_test.sh`.
- **Cause:** When pimsync recaptured the same UID with changed raw Local or Remote ICS, helper replaced stored versions but always kept old `choice`. A later `conflict-apply` could apply that stale choice automatically without asking user again.
- **Fix:** Preserve stored choice only if both raw ICS versions are byte-identical to previous capture; clear choice when either changes.
- **Verification:** Repeating capture with unchanged sources keeps choice; recapturing changed remote source clears it and `conflict-apply` refuses to act until a fresh choice. Red before fix, green after; full aggregate and static checks pass.

### 15. Clean source tree could not build parser objects — fixed

- **Location:** `parse/Makefile`, all `output/*.o` targets.
- **Cause:** Tracked generated object files previously kept `parse/output/` present. After removing generated files from source control, a clean checkout has no `output/`, while compilation still writes object files there without creating the directory.
- **Fix:** Add an `output` directory target as order-only prerequisite for each object target. `make clean` still removes generated objects; next build recreates the directory.
- **Verification:** Removing the empty directory after `make clean` caused `Fatal error: can't create output/helper.o`. After fix, `make -C parse test` creates `output/` and passes.

### 16. Successful import ran needless cleanup subprocess — simplified with approval

- **Location:** `services/CalendarService.qml`, `importCommitProcess.onExited()`; `dev/tests/test-profile-wiring.js`.
- **Finding:** Successful `convert commit` atomically renames the staging file into final location, so staging path no longer exists. QML nevertheless started `rm -f` and waited for a separate cleanup process before reporting import success.
- **Decision:** User approved skipping cleanup on success while retaining failure cleanup.
- **Change:** Clear pending import and publish the already-successful registry result immediately after commit. Error paths keep `importCleanupProcess`.
- **Verification:** Executed `onExited(0)` in a functional test with `cleanupImport` set to fail if called. Red before fix, green afterward; aggregate tests and QML lint pass.

### 17. Unchanged converted JSON triggered needless store reloads — simplified with approval

- **Location:** `parse/main.cpp`, `generate()`; `parse/test/converter_test.sh`.
- **Finding:** Converter replaced JSON even when bytes were unchanged. FileView watchers could then reload and re-normalize events, including feed refreshes with no source changes. Synced cache writer already avoided equal-content replacement.
- **Decision:** User approved immediate optimization.
- **Change:** Compare existing output bytes with serialized contents; skip atomic replacement when equal. Real changes continue through `writeAtomicallyFile()`.
- **Verification:** Repeating unchanged conversion retains inode; changing input produces a different output inode and data. Red before fix, green after; aggregate tests pass.

### 18. Dynamic calendar names and file paths used rich-text autodetection — fixed

- **Location:** `ui/EventEditorPanel.qml` calendar combo box; `ui/CalendarManagerPanel.qml` source selector, picker path, and file/folder entries; `dev/tests/test-plain-text-wiring.js`.
- **Cause:** These `Text` components omitted `textFormat: Text.PlainText`. Calendar names and paths can contain markup-like characters, so Qt's `Text.AutoText` could render them as rich text or request resources.
- **Fix:** Set explicit plain-text format on all five dynamic bindings. Existing event titles, conflict values, and legend entries were already plain text.
- **Verification:** Static binding test failed on source path before fix and passed after; full aggregate tests and QML lint pass.

### 19. Test-only calendar math exports — removed with approval

- **Location:** `common/CalendarMath.js`, `monthGridStart()`/`weekCount()`; `dev/tests/test-calendar-math.js`, `dev/tests/test-month-navigation.js`.
- **Finding:** Neither function had a production caller. Historical month navigation tests alone used them.
- **Decision:** User approved removing runtime-dead exports immediately.
- **Change:** Delete both functions and obsolete direct assertions. Month navigation test retains its active ListView, date boundary, and zoom checks; it computes its fixture's week count locally.
- **Verification:** Both focused test files and full aggregate suite pass. No production or test references remain.

### 20. Duplicate valid DISPLAY alarms broke imported/synced cache validation — fixed

- **Location:** `parse/helper.cpp`, `parseCalendar()`; `parse/test/parser_tests.cpp`.
- **Cause:** Each DISPLAY `VALARM` pushed its trigger minute into `Event.reminders`. Multiple alarms with the same trigger are valid ICS, but imported and synced JSON consumers reject duplicate `minutesBefore` values and could mark the whole calendar unavailable.
- **Fix:** Canonicalize duplicate supported reminder minutes while parsing ICS; raw ICS remains unchanged until an explicit event edit.
- **Verification:** Two equal -PT15M alarms failed unique-reminder regression before fix and yield one 15-minute reminder afterward. Parser, sync-helper, and aggregate suites pass.

### 21. General editor error still allowed rich-text rendering — fixed

- **Location:** `ui/EventEditorPanel.qml` general `root.errorMessage` Text; `dev/tests/test-plain-text-wiring.js`.
- **Cause:** Reminder-specific error was plain text, but second general error Text used `Text.AutoText`. External helper stderr and storage errors can include user-controlled text.
- **Fix:** Set `textFormat: Text.PlainText` on general error. Update binding test to check every occurrence of a specified text binding instead of only the first one.
- **Verification:** New test failed at second editor error before fix and passes after. Aggregate tests and QML lint pass.

### 22. Synced update could complete against stale cache or invite duplicate retry — fixed

- **Location:** `services/CalendarService.qml`, `finishSyncedMutation()`; `dev/tests/test-synced-reload.js`.
- **Cause:** Update completion checked only whether source UID remained present, which was already true in old cache before FileView reload. It returned the raw event without normalized timestamps. If reload failed for 5 seconds after helper exit 0, UI reported an uncommitted failure even though canonical ICS had changed, permitting a duplicate create retry.
- **Fix:** Compare normalized cache fields, reminders, and timestamps to expected mutation; keep waiting while old values remain. Return normalized updated event. On reload timeout, report committed cache-warning result and instruct user not to retry.
- **Verification:** Executed actual QML function in a JS VM with stale then updated cache, ISO timestamp with/without `.000`, and timeout. Test failed before fix, passed after; full aggregate and QML lint pass.

### 23. Redundant calendar property alias — simplified with approval

- **Location:** `services/CalendarService.qml`, `sourceCalendars` and `calendars`; `dev/tests/test-synced-reload.js`.
- **Finding:** Public `calendars` was an alias of `sourceCalendars`, while internal service methods read `sourceCalendars`. No distinct state or transformation existed.
- **Decision:** User approved removing alias.
- **Change:** Compute public `calendars` directly and use it internally. Update functional reload test fixture to provide the public property.
- **Verification:** Focused Node tests, QML lint, and aggregate suite pass.

### 24. Conflict Confirm looked actionable with invalid state — fixed

- **Location:** `ui/ConflictResolutionPanel.qml`, `confirmChoice()` and Confirm controls; `dev/tests/test-conflict-state.js`.
- **Cause:** Conflict service rejected `choose()` while state was invalid, but panel still set `confirmPending = true` and left Confirm enabled when side was selected.
- **Fix:** Require `stateValid` before starting confirmation; disable Confirm hover/click and reduce opacity while state is invalid. Error message remains visible.
- **Verification:** Functional panel test observed false pending and no choice call only after fix; QML lint and aggregate suite pass.

### 25. Valid lowercase VEVENT components could not be edited — fixed

- **Location:** `parse/helper.cpp`, `preservedProperties()` and `writeEventFilePreserving()`; `parse/test/parser_tests.cpp`.
- **Cause:** libical accepts case-insensitive component/property names, but raw edit code searched only uppercase `BEGIN:VEVENT`/`END:VEVENT` and alarm boundaries. Editing valid lowercase ICS returned an error instead of preserving unknown fields.
- **Fix:** Match component boundary lines case-insensitively while preserving original VCALENDAR prefix/suffix and unknown event properties. Continue failing safely if original boundaries are absent.
- **Verification:** Lowercase component/field fixture parses successfully; edit originally failed and now retains `X-CUSTOM`, updates summary, and reparses. Parser and sync-helper suites pass.

## Second-pass review and remaining boundaries

- Rechecked changed native writer, UID/revision validation, conflict selection/capture/apply, and imported cache contracts. Regression fixtures cover failed writes, malformed input, unknown ICS properties, and duplicate UIDs/alarms.
- Rechecked QML profile loading, local/synced mutation dispatch, stale cache completion, visible events, and conflict panel state transitions. No further confirmed defect found in that pass.
- Import has separate registry and cache commits. A process crash between commits can leave a missing imported profile or staged file. Existing fallback preserves canonical/source data; automatic recovery across process crashes is not implemented or covered by this audit. Do not describe this flow as a cross-file transaction.
- FileView startup warnings for missing optional imports/conflict state in disposable runtime data are expected. Test logs contained no binding or import errors.
- Runtime smoke launched only calendar config using isolated data; `calendar.toggle` IPC returned `true`. Real pimsync/CalDAV server interaction was not exercised by that smoke test; broker has fake-command tests.

## Findings deferred by user decision

### Single-file import has a 2-second stability wait

- **Location:** `parse/main.cpp`, `waitForStableFiles()` (`settleTime = 2s`), called for both directory feeds and selected single-file imports.
- **Effect:** An explicit ICS file import waits at least 2 seconds before parsing. This is per import, not a continuously polling process.
- **Decision:** User chose to keep and log the delay. Shortening it would reduce time allowed for an ICS source still being written; no code change.

### Synced event mutations rebuild full JSON cache

- **Location:** `parse/sync_main.cpp`, `mutate()` calls `rebuildUnlocked()` after canonical ICS commit. Rebuild iterates and parses each ICS file, then serializes the full cache.
- **Cost:** O(number of ICS files) for each create, update, or delete. No continuous polling is added; cost occurs per mutation.
- **Decision:** User chose to keep and log full rebuild. It simplifies canonical-ICS recovery. Profile with realistic calendar size before considering incremental cache mutation.

### Source-text wiring tests remain brittle

- **Location:** `dev/tests/test-profile-wiring.js`, `dev/tests/test-conflict-wiring.js`, and related source-text assertions.
- **Effect:** Assertions against exact QML source spelling may fail after harmless refactors or pass while behavior is disconnected. Focused VM, native helper, and shell tests provide stronger behavioral checks for selected paths.
- **Decision:** User chose to keep these checks until the separate test-cleanup pass. Replace source-text checks only after coverage of their actual UI/backend interactions exists; preserve plain-text render coverage.

## Audit gate and disposition

Each accepted fix received focused red/green regression and aggregate test verification. Final clean build (`make -C parse clean && make -C parse test`), full `qmllint`, shell syntax, and `git diff --check` passed. A post-change smoke test launched only calendar config with isolated XDG data; `calendar.toggle` IPC returned `true`, and Quickshell logged `Configuration Loaded` without QML binding/import errors. Missing optional files in isolated storage produced expected FileView warnings. Test instance and disposable data were removed. Generated binaries/objects were cleaned afterward. Snapshot integrity and unchanged `install.sh` SHA-256 (`1130fd89fa1498f46aed86028bd4b7c1e4ea1a2139522f0a42d6d161c5860609`) were verified before snapshot removal. Deferred items above require new user direction before changing behavior or deleting test history.
