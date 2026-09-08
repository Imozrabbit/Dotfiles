# Calendar Implementation Plan

**Goal:** Build a standalone, dark Quickshell calendar against a mocked
`CalendarService`, starting with a reliable Week View.

**Architecture:** `shell.qml` composes one service and one window. The service
normalizes and filters data once. Pure calendar math remains in one tested JS
module; QML views only render service-owned data and derived layout records.

**Tech stack:** Quickshell, QML, JavaScript, Node built-in assertions.

## Global Constraints

- Project root is this `calendar` directory.
- `instruction.md` is the requirements source of truth.
- No ICS, pimsync, helper transport, synchronization, daemon, or event timers.
- No `DankCommon`, `dank-qml-common`, or new runtime dependency.
- Work one approved stage at a time and verify before advancing.

## Stage Ledger

| Stage | Status | Evidence |
|---|---|---|
| 1. Donor audit | Complete | Approved 2026-08-30 |
| 2. Mock service and Week View | Complete | Runtime confirmed 2026-08-30 |
| 2.1 Compact timetable density | Rejected | Manual evaluation 2026-08-30 |
| 2.2 Adjustable vertical zoom | Superseded | Manual feedback 2026-08-30 |
| 2.3 Ctrl+wheel zoom refinement | Failed runtime | WheelHandler received no events |
| 2.4 Zoom input fix | Complete | Runtime confirmed 2026-08-30 |
| 3a. Month View | Complete | Runtime accepted 2026-08-31 |
| 3a.1 Rolling Month redesign | Superseded | More zoom and scrolling requested |
| 3a.2 Scrollable Month buffer | Approved | 27 weeks, 2W-6W zoom |
| 3a.3 Month boundary markers | Approved | Apple-like label on each day 1 |
| 3a.4 Month boundary contrast | Superseded | Accent borders rejected in runtime |
| 3a.5 Twelve-month palette | Approved | No accent borders; unique month hues |
| 3a.6 Full-year Month range | Approved | Continuous selected calendar year |
| 3a.7 Today card outline | Approved | Full-cell current-time red border |
| Month navigation performance | Implemented | Node tests and targeted QML lint pass; manual runtime pending |
| Calendar data preparation optimization | Implemented | Month event bucketing; Node tests and targeted QML lint pass; runtime profiling pending |
| Agenda grouping optimization | Implemented | Date-key lookup replaces per-event day scan; CalendarMath tests pass |
| Range filtering optimization | Implemented | Calendar visibility index replaces per-event calendar lookup; CalendarMath tests pass |
| Month model allocation optimization | Implemented | Reuses bucket dates during week assembly; full Node suite and QML lint pass |
| Month interval-loop optimization | Implemented | Skips non-overlapping midnight boundary day; full Node suite passes |
| Month event allocation optimization | Implemented | Reuses single-day source events; clones only clipped segments; full suite passes |
| Service normalization optimization | Implemented | Immutable source events normalize once; personal events retain dynamic normalization |
| Runtime optimization profiling | Smoke verified | Clean startup and IPC toggle after removing stale `.qmlls.ini`; interactive UI timing still unmeasured |
| 3b. Agenda/Day View | Complete | Runtime accepted 2026-08-31 |
| 3c. Event details | Approved | Shared read-only right drawer |
| 3c.1 Month delayed-callback fix | Implemented | Runtime confirmation pending |
| 3c.2 Header/legend cleanup | Approved | Right-click Today resets zoom |
| 3c.3 Details modal input fix | Implemented | Runtime confirmation pending |
| 3c.4 Month tint contrast | Approved | Background alpha 0.08 -> 0.12 |
| 3c.5 Modern month palette | Approved | Balanced Spectrum; no selected styling |
| 3d. Calendar visibility | Complete | Runtime confirmed 2026-09-01 |
| 4a. Card selection | Complete | Runtime confirmed 2026-09-01 |
| 4b. Mocked mutations | Complete | Runtime confirmed 2026-09-03 |
| 4. Mocked mutations | Complete | Runtime confirmed 2026-09-03 |
| 5. Reminder interface | Implemented | Static verification complete; runtime pending |

## Donor Baseline

- Repository: <https://github.com/AvengeMedia/dankcalendar>
- Commit: `29bf5558ffcb1460d703b70ab687fa3b66a5fb5a`
- Primary basis: `quickshell/Modules/views/WeekView.qml`
- Extracted behavior: `quickshell/Services/DankCalService.qml`
- Navigation reference: `quickshell/Modules/CalendarWindow.qml`
- Test reference: `quickshell/tests/tst_EventUtils.qml`
- Visual references only: `quickshell/Common/Theme.qml` and `StockTheme.js`

## Stage 2 Interfaces

`common/CalendarMath.js` produces:

```js
weekStart(date)
addDays(date, days)
dayStart(date)
rangesOverlap(startA, endA, startB, endB)
layoutTimedEvents(events)
normalizeEvent(event, calendars)
filterEventsInRange(events, calendars, start, end)
wallClockRange(start, end, day)
```

`services/CalendarService.qml` exposes:

```qml
property var calendars
property var events
function eventsInRange(start, end)
function calendarById(calendarId)
```

Normalized timed events retain ISO `start` and `end` values and add finite
`startMs` and `endMs`. All-day events retain exclusive `YYYY-MM-DD` bounds and
add local-midnight `startMs` and `endMs`. Invalid records never enter `events`.

## Stage 2 Tasks

### 1. Pure Calendar Math

**Files:**

- Create `tests/test-calendar-math.js`
- Create `common/CalendarMath.js`

- [x] Write checks for Monday week alignment across month boundaries.
- [x] Write checks proving adjacent half-open intervals do not overlap.
- [x] Write checks for two-way and transitive overlap columns.
- [x] Write check proving layout does not mutate source events.
- [x] Run `node tests/test-calendar-math.js` and verify missing implementation fails.
- [x] Implement minimum functions and rerun until all checks pass.

### 2. Mock Service

**Files:**

- Create `services/CalendarService.qml`

- [x] Define `edt_unistra` read-only and `personal` writable calendars.
- [x] Add normal, overlapping, all-day, writable, read-only, and malformed raw
  fixtures.
- [x] Normalize timestamps once and reject missing IDs, unknown calendars,
  invalid dates, and non-positive ranges.
- [x] Implement visible-calendar half-open range filtering.

### 3. Standalone Week View

**Files:**

- Create `shell.qml`
- Create `common/Theme.js`
- Create `ui/CalendarWindow.qml`
- Create `ui/WeekView.qml`
- Create `ui/EventCard.qml`

- [x] Compose one service and one visible window.
- [x] Add original muted dark tokens without a theme framework.
- [x] Add Monday-Sunday header and Today/previous/next controls.
- [x] Add all-day lane and 24-hour native `Flickable` grid.
- [x] Position timed cards from tested layout records.
- [x] Add one shared minute clock and current-week/day indicator.
- [x] Keep interactions read-only in Stage 2.

### 4. License And Verification

**Files:**

- Create `licenses/DankCalendar-MIT.txt`

- [x] Preserve complete pinned upstream MIT notice.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`.
- [x] Run `qmllint` on every QML file.
- [x] Ask whether user or assistant performs runtime smoke test.
- [x] Update this ledger with results and report donor basis, changed files,
  removed dependencies, remaining mocks, and known limits.

## Stage 2 Verification

- Pure JS tests: pass, including malformed input, half-open ranges, overlapping
  columns, non-mutation, all-day exclusivity, and Europe/Paris DST folds.
- `qmllint`: clean for `shell.qml`, service, window, Week View, and event card.
- Independent review: no remaining findings after three fix cycles.
- Runtime smoke test: passed by manual user confirmation.
- Real-data sampling: read-only inspection of `~/.local/share/calendars` informed
  mock UTC timestamps, opaque UIDs, Unicode titles, long/optional locations,
  and multiline descriptions. No ICS handling was added.

## Deferred

Swipe paging, drag/drop, selection, event details, calendar visibility UI,
Month View, Agenda/Day View, CRUD, persistence, helper transport, ICS, and
notifications remain outside Stage 2.

## Stage 2.1: Compact Timetable Density

**Goal:** Make the minimum-height window show the typical 07:00-18:00
university timetable without removing access to the full day.

**Change:** Set `ui/WeekView.qml` `hourHeight` from `72` to `40`. Keep the
07:00 initial scroll position, fixed 24-hour grid, vertical scrolling, event
content, and window minimum size unchanged.

**Acceptance:** At the minimum window height, roughly 11 hours are visible and
two-hour event cards remain readable. Existing calendar math tests and QML lint
must stay clean; runtime result is evaluated manually before considering zoom.

### Execution Checklist

**File:** Modify `ui/WeekView.qml:12` only.

- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js` for baseline.
- [x] Change `readonly property int hourHeight: 72` to `40`.
- [x] Run the calendar math test again.
- [x] Run `qmllint ui/WeekView.qml`.
- [x] Ask the user to evaluate the minimum-height view manually.

No automated test targets the literal visual density value: such a test would
only detect source-text changes, not rendering behavior. Existing geometry
tests and manual runtime evaluation cover meaningful behavior.

## Stage 2.2: Adjustable Vertical Zoom

**Goal:** Restore the detailed default density while allowing temporary compact
or expanded vertical scaling and starting the viewport at 08:00.

**Behavior:**

- Restore default density to `72px/hour`, displayed as `100%`.
- Offer discrete levels: `40`, `48`, `60`, `72`, `84`, `96`, and
  `108px/hour`.
- Add header `-`, percentage/reset, and `+` controls.
- Clicking percentage resets to `72px/hour`.
- Ctrl+wheel over the timed grid uses the same levels; ordinary wheel input
  continues vertical scrolling.
- Preserve the time at viewport center while zoom changes.
- Set initial timed-grid position to 08:00.
- Keep zoom session-only; add no persistence or I/O.

**Implementation Boundary:** Put zoom levels, next-level selection, percentage,
and anchored scroll-offset calculation in tested `common/Zoom.js`. Keep
`ui/WeekView.qml` responsible for grid state and Ctrl+wheel handling, and
`ui/CalendarWindow.qml` responsible for visible header controls.

**Acceptance:** Controls clamp at minimum/maximum, reset returns to `100%`,
normal wheel scrolling remains available, zoom preserves center time, initial
position is 08:00, existing calendar behavior remains green, and manual runtime
evaluation confirms useful interaction.

### Execution Checklist

**Files:**

- Create `common/Zoom.js`
- Create `tests/test-zoom.js`
- Modify `ui/WeekView.qml`
- Modify `ui/CalendarWindow.qml`

**Pure interface:**

```js
nextHeight(currentHeight, direction)
percent(height)
anchoredOffset(contentY, viewportHeight, oldHeight, newHeight, maxOffset)
```

- [x] Write failing Node assertions: bounds clamp, `72 -> 84 -> 72`, `72` is
  `100%`, and center-time anchoring returns a literal expected offset.
- [x] Run `node tests/test-zoom.js`; expect missing-function failure.
- [x] Implement minimum `common/Zoom.js`; rerun until green.
- [x] Restore `WeekView.hourHeight` default to `72` and initial scroll to 08:00.
- [x] Add `zoomIn()`, `zoomOut()`, and `resetZoom()` methods preserving viewport
  center time through `Zoom.anchoredOffset()`.
- [x] Add Ctrl+wheel handling to the timed grid without consuming ordinary
  wheel scrolling.
- [x] Add header `-`, percentage/reset, and `+` controls wired to Week View.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js` and
  `node tests/test-zoom.js`.
- [x] Run `qmllint ui/WeekView.qml ui/CalendarWindow.qml`.
- [ ] Ask the user to perform the runtime interaction test.

## Stage 2.3: Ctrl+wheel Zoom Refinement

**Goal:** Keep zoom unobtrusive, make every step exactly 10%, and begin the
timed viewport at 07:30.

**Behavior:**

- Remove header zoom buttons and percentage display.
- Keep Ctrl+wheel as the only zoom interaction.
- Store zoom as an integer percentage from `50` through `150`, inclusive.
- Change one `10%` level per accepted wheel event; default remains `100%`.
- Derive `hourHeight` as `72 * zoomPercent / 100`.
- Preserve viewport center time and keep ordinary wheel scrolling unchanged.
- Set initial timed-grid position to `7.5 * hourHeight`.
- Keep zoom session-only.

**Implementation Boundary:** Change `common/Zoom.js` to percentage-first
helpers, update tests before implementation, simplify `ui/WeekView.qml` state,
and remove only zoom-specific header controls from `ui/CalendarWindow.qml`.

**Acceptance:** Zoom clamps at `50%` and `150%`, every step is exactly `10%`,
the default remains `100%`, no header zoom UI remains, Ctrl+wheel preserves
center time, normal wheel scrolls, and the initial top time is 07:30.

### Execution Checklist

**Files:**

- Modify `tests/test-zoom.js`
- Modify `common/Zoom.js`
- Modify `ui/WeekView.qml`
- Modify `ui/CalendarWindow.qml`

**Pure interface:**

```js
nextPercent(currentPercent, direction)
hourHeight(percent)
anchoredOffset(contentY, viewportHeight, oldHeight, newHeight, maxOffset)
```

- [x] Replace pixel-level assertions with literal percentage assertions:
  `100 -> 110 -> 100`, lower `50`, upper `150`, and heights `72`/`79.2`.
- [x] Run `node tests/test-zoom.js`; expect missing `nextPercent` failure.
- [x] Implement percentage-first helpers and remove pixel-level helpers.
- [x] Run `node tests/test-zoom.js`; expect pass.
- [x] Store `zoomPercent: 100` in Week View and derive real `hourHeight`.
- [x] Change Ctrl+wheel to update percentage and keep center anchoring.
- [x] Set initial offset to `7.5 * hourHeight`.
- [x] Remove zoom-specific header controls and unused reset method.
- [x] Run both Node test files and lint both changed QML files.
- [ ] Ask the user to perform runtime verification.

## Stage 2.4: Zoom Input Fix

**Root Cause:** On the installed Quickshell/Qt runtime, the nested
`WheelHandler` does not win wheel-event delivery against `Flickable`; zoom
policy works but its input callback never runs.

**Fix:** Replace the nested `WheelHandler` with a transparent full-grid
`MouseArea`. It accepts no mouse buttons, consumes Ctrl+wheel after changing one
10% zoom level, and rejects unmodified wheel events so Flickable keeps normal
vertical scrolling.

Restore header minus, percentage/reset, and plus controls. Keep Stage 2.3's
50%-150% range, 10% steps, 100% default, center anchoring, session-only state,
and 07:30 initial position unchanged.

**Acceptance:** Header controls update zoom and percentage, percentage resets
to 100%, Ctrl+wheel updates zoom, ordinary wheel scrolls, and no QML warning or
regression appears.

### Execution Checklist

**Files:**

- Modify `tests/test-zoom.js`
- Modify `common/Zoom.js`
- Modify `ui/WeekView.qml`
- Modify `ui/CalendarWindow.qml`

- [x] Add failing `wheelDirection(controlPressed, deltaY)` assertions: no Ctrl
  returns `0`, Ctrl+up returns `1`, Ctrl+down returns `-1`.
- [x] Run `node tests/test-zoom.js`; expect missing-function failure.
- [x] Implement `wheelDirection()` and rerun until green.
- [x] Replace `WheelHandler` with full-grid `MouseArea`; consume only nonzero
  `wheelDirection()` results and reject ordinary wheel events.
- [x] Restore `-`, percentage/reset, and `+` header controls.
- [x] Run both Node suites and lint changed QML files.
- [x] Request focused review of input propagation and controls.
- [x] Ask user to verify Ctrl+wheel and ordinary wheel behavior manually.

## Stage 3a: Month View

**Goal:** Add a useful read-only Month View without keeping inactive heavy views
alive or duplicating service/date logic.

**Architecture:** `CalendarWindow` owns one `selectedDate` and active view name.
A `Loader` creates either Week View or Month View. Week View receives
`weekStart(selectedDate)`; Month View receives `selectedDate`. Previous/next
navigation moves seven days in Week mode and one clamped month in Month mode.
Today and Week/Month switching preserve one valid shared date.

**Month View:** Add a Monday-first fixed 6x7 grid. Each cell shows day number,
muted styling outside selected month, today/selected state, up to three compact
color-coded event title chips, and `+N more` overflow. Query `CalendarService`
once for the 42-day range. Group normalized events using existing half-open
overlap semantics; all-day and multi-day events appear once per intersected
day.

**Data:** Add mock events exercising previous/next month boundaries, a
multi-day all-day span, and at least four events on one day. Do not add parser,
helper, persistence, mutation, details, visibility, or Agenda behavior.

**Verification:** Test Monday grid alignment, six-week range, and clamped month
navigation before implementation. Run all existing tests and QML lint. Manual
runtime verification covers view switching, navigation, overflow, and minimum
window layout.

### Execution Checklist

**Files:**

- Modify `tests/test-calendar-math.js`
- Modify `common/CalendarMath.js`
- Modify `services/CalendarService.qml`
- Create `ui/MonthView.qml`
- Modify `ui/CalendarWindow.qml`

**Pure interfaces:**

```js
monthGridStart(date)
addMonthsClamped(date, delta)
```

- [x] Add failing assertions: September 2026 grid starts Monday August 31,
  six weeks end exclusively October 12, January 31 plus one month clamps to
  February 28, and subtracting restores a valid January date.
- [x] Run `node tests/test-calendar-math.js`; expect missing-function failure.
- [x] Implement minimum month helpers and rerun until green.
- [x] Add mock boundary, multi-day all-day, and four-event crowded-day data.
- [x] Create Month View with one 42-day service query, 6x7 cells, three compact
  chips, and overflow label.
- [x] Refactor CalendarWindow to shared `selectedDate`, active-view `Loader`,
  mode-aware navigation, segmented Week/Month controls, and Week-only zoom UI.
- [x] Run both Node suites and lint every changed QML file.
- [x] Request correctness review for navigation, model duplication, boundaries,
  and minimum-size geometry.
- [ ] Ask user to perform runtime verification.

## Stage 3a.1: Rolling Month Redesign

**Goal:** Replace the conventional 6x7 month grid with an Apple-inspired
rolling multi-week view that shows every event with reduced detail.

**Layout:** Start at `weekStart(selectedDate)` and render Monday-first week
bands. Default page contains three weeks; zoom-in contains two. Each day shows
date plus every normalized event as a compact colored title/time label. No
overflow counter or hidden event. Each row receives an equal viewport share but
expands when its busiest day needs more event space; the outer page then scrolls
instead of clipping data.

**Navigation And Zoom:** Previous/next shifts one complete page using current
week count. Today returns to current week. Month header controls show minus,
`3W`/`2W` reset, and plus; Ctrl+wheel uses the same two levels. Three weeks is
default/reset. Week View keeps independent percentage zoom state.

**Architecture:** Keep one lazy active view and one shared selected date.
Month View queries `CalendarService` once for its 14- or 21-day page and groups
events by existing half-open overlap semantics. Remove conventional month-grid
overflow and out-of-month styling. Do not add details, mutation, visibility, or
Agenda behavior.

**Acceptance:** Default shows three weeks starting at selected/current week;
zoom switches between three and two; arrows shift by current page size; every
event remains represented; busy rows expand without overlap; ordinary wheel
scrolls expanded content; minimum window remains usable.

### Execution Checklist

**Files:**

- Modify `tests/test-zoom.js`
- Modify `common/Zoom.js`
- Rewrite `ui/MonthView.qml`
- Modify `ui/CalendarWindow.qml`

**New pure interface:**

```js
nextWeeksPerPage(currentWeeks, direction)
```

- [x] Add failing assertions: default `3`, zoom-in `3 -> 2`, zoom-out `2 -> 3`,
  and both bounds clamp.
- [x] Run `node tests/test-zoom.js`; expect missing-function failure.
- [x] Implement `nextWeeksPerPage()` and rerun until green.
- [x] Rewrite Month View around `weekStart(selectedDate)`, `weeksPerPage`, one
  page-range query, week-band models, and all event labels without slicing.
- [x] Add dynamic minimum week-row heights and outer vertical Flickable.
- [x] Add Month Ctrl+wheel filtering and `zoomIn/zoomOut/resetZoom` methods.
- [x] Store Month zoom state in CalendarWindow, make zoom controls mode-aware,
  and navigate by `weeksPerPage * 7` days.
- [x] Run both Node suites and lint Month View plus CalendarWindow.
- [x] Request review for hidden events, row geometry, paging, input routing, and
  independent Week/Month zoom state.
- [ ] Ask user to perform runtime design verification.

## Stage 3a.2: Scrollable Month Buffer

**Goal:** Allow free vertical week scrolling and broader Month zoom without
unbounded models or event queries.

**Buffer:** Load 27 Monday-first week bands: selected week, 13 previous, and 13
future. Initial position puts selected/current week at viewport top. Ordinary
wheel input scrolls continuously through buffer. Busy rows still expand so no
event is hidden.

**Zoom:** Support `2W`, `3W`, `4W`, `5W`, and `6W`; default/reset is `3W`.
Header controls and Ctrl+wheel change one level while preserving top-visible
week. Previous/next shifts selected anchor by current visible-week count and
rebuilds centered buffer.

**Shared State:** Month View exposes top-visible week date as scrolling changes.
Header month/year follows it. Switching back to Week uses that visible week.
Today recenters buffer on current week. Week percentage zoom remains independent.

**Performance:** Keep one service query for 189-day buffer and no polling,
timers, persistence, or incremental edge loaders. Rebuild only when anchor,
calendar data, or zoom-dependent geometry changes.

**Acceptance:** Normal wheel scrolls both directions; initial top is selected
week; all five zoom levels work and preserve visible week; arrows jump by active
page size; header follows scroll; Week switch opens visible week; all events
remain represented; model remains bounded to 27 weeks.

### Stage 3a.2 Execution Plan

**Architecture:** Keep zoom policy in `common/Zoom.js`. Keep date buffering,
week geometry, visible-week tracking, and vertical scrolling inside
`ui/MonthView.qml`; expose only `visibleDate` to `ui/CalendarWindow.qml` for
header, navigation, Today, and view switching.

**Constraints:** No new files, dependencies, persistence, timers, backend work,
or unbounded incremental loading. Monday-first behavior and independent Week
zoom remain unchanged.

#### Task 1: Extend Month Zoom Policy

**Files:** Modify `tests/test-zoom.js` and `common/Zoom.js`.

**Interface:** `nextWeeksPerPage(currentWeeks, direction)` returns an integer in
`[2, 6]`; positive direction zooms in by one week and negative zooms out by one.

- [x] Add assertions for `3 -> 4 -> 5 -> 6` zoom-out and upper-bound clamping.
- [x] Run `node tests/test-zoom.js`; new `3 -> 4` assertion failed with `3 !== 4`.
- [x] Change only upper clamp from `3` to `6`.
- [x] Rerun test; output was `Zoom tests passed`.

#### Task 2: Add Bounded Continuous Month Scrolling

**Files:** Modify `ui/MonthView.qml` and `ui/CalendarWindow.qml`.

**Interfaces:** `MonthView.visibleDate` reports Monday of top-visible week.
Existing `zoomIn()`, `zoomOut()`, and `resetZoom()` preserve that week. Existing
window controls consume `visibleDate`; no new public component is introduced.

- [x] Replace page-sized event/model range with 27 weeks centered on
  `weekStart(selectedDate)` and initialize `contentY` at buffered week index 13.
- [x] Add helpers that map `contentY` to week index/date and position a buffered
  date at viewport top; use them after zoom and selected-date changes.
- [x] Let ordinary wheel events reach Flickable while Ctrl+wheel changes one
  `2W-6W` level; update `visibleDate` from vertical movement.
- [x] Store `monthVisibleDate` in CalendarWindow; bind title, arrows, Today, and
  Month-to-Week switching to top-visible date without changing Week behavior.
- [x] Add tested trailing viewport padding so edge weeks remain top-visible
  across all zoom levels.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js` and
  `node tests/test-zoom.js`; expect both suites to pass.
- [x] Run `qmllint ui/MonthView.qml ui/CalendarWindow.qml`; no diagnostics.
- [x] Request focused review; trailing-edge finding fixed and rereview passed.
- [x] Ask whether user wants manual or assistant runtime smoke testing before
  running Quickshell.
- [x] User manually verifies continuous scrolling, `2W-6W` zoom, navigation,
  Today recentering, header updates, and Month-to-Week handoff.

## Stage 3a.3: Month Boundary Markers

**Goal:** Make every month transition clear inside continuous Monday-first week
scrolling, matching Apple's inline treatment without splitting or duplicating
boundary weeks.

**Presentation:** A week containing day `1` gains a compact transition strip.
The first-day cell shows full month name above its day number in stronger text,
and a subtle horizontal rule marks the transition week. Other day cells retain
their normal date treatment.

**Geometry:** Transition strip increases only that week's minimum height. Date
numbers and events shift down together in transition weeks. Existing busy-row
expansion remains authoritative, so month labels never overlap events and no
event is hidden.

**Constraints:** Keep one continuous 27-week model, Monday-first rows, existing
scroll/zoom/visible-date behavior, month-only labels, dark theme, and current
event rendering. Do not add month components, duplicate dates, or change
CalendarWindow state.

**Acceptance:** Every day `1` in buffer has one full month label; split weeks
stay chronological; transition labels, date numbers, and events do not overlap;
all non-transition weeks retain current spacing; `2W-6W` zoom and scrolling keep
working.

### Stage 3a.3 Execution Plan

**Architecture:** Add one pure `CalendarMath.monthStartIndex(weekStartDate)`
helper for detecting day `1` inside a Monday-Sunday row. MonthView stores that
index in each existing week object and derives transition spacing/rendering from
it; no new QML component or state path.

**Constraints:** Keep 27 weeks, Monday-first order, bounded scrolling, `2W-6W`
zoom, top-visible-date behavior, event rendering, and CalendarWindow unchanged.

#### Task 1: Detect Month Starts in Week Rows

**Files:** Modify `tests/test-calendar-math.js` and `common/CalendarMath.js`.

**Interface:** `monthStartIndex(weekStartDate)` returns `0-6` for day `1` in that
seven-day row, or `-1` when no month starts there.

- [x] Add assertions for May 1, 2025 at index `3`, a no-boundary week at `-1`,
  and January 1, 2026 at index `3`.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`; failed because
  `monthStartIndex` was missing.
- [x] Implement seven-day scan using existing DST-safe `addDays()` and export it.
- [x] Rerun test; output was `CalendarMath tests passed`.

#### Task 2: Render Apple-Like Month Boundaries

**Files:** Modify `ui/MonthView.qml`.

**Interface:** Each existing week object gains integer `monthStartIndex`.
`weekHeaderInset(index)` returns `22` for transition weeks and `0` otherwise.

- [x] Store `CalendarMath.monthStartIndex(days[0].date)` in each built week.
- [x] Include `weekHeaderInset(index)` in minimum week height.
- [x] Add subtle top rule visible only when `monthStartIndex >= 0`.
- [x] Show `Qt.formatDate(date, "MMMM")` above day number only in first-day cell.
- [x] Offset all date numbers and events by transition inset for that week.
- [x] Run both Node suites and `qmllint ui/MonthView.qml`; clean output.
- [x] Request focused review for split-week indexing, overlap, variable geometry,
  scroll mapping, and zoom preservation; no code issues found.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] User manually verifies labels, transition rules, spacing, scrolling, and
  `2W-6W` zoom across at least two month boundaries.

## Stage 3a.4: Month Boundary Contrast

**Goal:** Make adjacent months immediately distinguishable during scrolling
without overpowering events or changing calendar geometry.

**Treatment:** Cells in alternating calendar months receive a 5% accent-colored
background tint based on year/month parity. Untinted months keep the existing
background. Selected-day background remains authoritative. Each day `1` gains a
2px vertical accent edge, the existing transition-week rule becomes 2px with
stronger opacity, and month-name text uses the accent color.

**Constraints:** Modify only `ui/MonthView.qml`. Derive tint from `Theme.accent`;
do not add theme tokens, components, state, model fields, spacing, or event
changes. Preserve dark-theme contrast, Today marker, scrolling, `2W-6W` zoom,
selection, dynamic row geometry, and visible-date behavior.

**Acceptance:** Adjacent months have visibly different but restrained hues;
split-week ownership changes exactly at day `1`; boundary line and month label
remain clear at every zoom; selected cells and events remain legible; geometry
and interaction behavior do not change.

### Stage 3a.4 Execution Plan

**Architecture:** Use existing day-cell date and `Theme.accent` directly in
`ui/MonthView.qml`. Calendar month parity controls a translucent background;
existing selected state overrides it. Existing transition elements receive only
visual property changes.

**Constraints:** One-file declarative styling change. No model, helper, theme,
geometry, event, state, dependency, or interaction changes.

#### Task 1: Increase Month Boundary Contrast

**File:** Modify `ui/MonthView.qml`.

**Interface:** `dayColumn.tintedMonth` is true when
`(year * 12 + month) % 2 !== 0`; `root.monthTint` resolves `Theme.accent` as a
QML color for channel blending.

- [x] Add `root.monthTint` and per-day `tintedMonth` readonly properties.
- [x] Use 5% `monthTint` for unselected cells in alternating months; preserve
  `Theme.surfaceRaised` for selected cells and `Theme.background` otherwise.
- [x] Change transition rule to 2px and 60% opacity.
- [x] Add 2px, 75%-opacity accent edge at left side of every day `1` cell.
- [x] Change month-name text to accent color and 14px DemiBold.
- [x] Run both Node suites and `qmllint ui/MonthView.qml`; clean output.
- [x] Request focused review for selection precedence, color contrast, exact
  split-week boundary, event readability, and unchanged geometry; no issues.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] Runtime feedback rejected accent borders and two-color hue rotation;
  superseded by Stage 3a.5.

## Stage 3a.5: Twelve-Month Palette

**Goal:** Replace disliked blue boundary borders and two-state tint rotation with
twelve distinct, restrained month identities.

**Palette:** January `#7fa7d8`, February `#b58ac8`, March `#78b99a`, April
`#a9c96b`, May `#58b7a8`, June `#d8b45f`, July `#dd8a5b`, August `#d87885`,
September `#c89a55`, October `#c37052`, November `#9582c5`, December `#63a9bc`.
Each day-cell background blends its month color at 8% opacity. Each month name
uses its matching color at full opacity.

**Removal:** Delete both Stage 3a.4 accent boundaries: full-width transition-week
rule and vertical day-1 edge. Retain only existing neutral calendar grid/bottom
lines. Keep day-1 month labels and transition spacing from Stage 3a.3.

**Constraints:** Modify only `ui/MonthView.qml`. Selection remains authoritative
over month tint. Today, events, geometry, 27-week buffer, scrolling, `2W-6W`
zoom, visible-date tracking, and CalendarWindow behavior remain unchanged.

**Acceptance:** All twelve month indexes map to one stable distinct color across
years; split weeks change hue exactly at month boundary; no blue/accent boundary
line remains; month label matches cell hue; selected cells and events remain
legible; no geometry or interaction behavior changes.

### Stage 3a.5 Execution Plan

**Architecture:** Replace `monthTint`/`tintedMonth` parity logic with one
12-entry `monthColors` array indexed by `Date.getMonth()`. Each day delegate
resolves one `monthColor` used by its background and optional month label.

**Constraints:** Modify only `ui/MonthView.qml`; no new helpers, model fields,
theme values, components, geometry, state, dependencies, or interactions.

#### Task 1: Replace Parity Tint and Accent Borders

**File:** Modify `ui/MonthView.qml`.

**Interface:** `root.monthColors[0-11]` contains exact Stage 3a.5 palette;
`dayColumn.monthColor` is indexed by `modelData.date.getMonth()`.

- [x] Replace `monthTint` with exact 12-color `monthColors` array.
- [x] Replace `tintedMonth` with per-day `monthColor`.
- [x] Blend every unselected day background from `monthColor` at 8% opacity;
  keep selected `Theme.surfaceRaised` path unchanged.
- [x] Delete full-width accent transition-rule Rectangle.
- [x] Delete vertical day-1 accent-edge Rectangle.
- [x] Bind month-name text color to `dayColumn.monthColor`.
- [x] Run both Node suites and `qmllint ui/MonthView.qml`; clean output.
- [x] Request focused review for all 12 indexes, year rollover, border removal,
  selection precedence, event contrast, and unchanged geometry; no issues.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] User manually verifies 12 month hues, matching labels, no accent border,
  selection/event contrast, scrolling, and `2W-6W` zoom.

## Stage 3a.6: Full-Year Month Range

**Goal:** Let Month View scroll through the complete selected calendar year
instead of stopping 13 weeks after selected date.

**Range:** Start at Monday containing January 1 of `selectedDate` year. End at
exclusive Monday after week containing December 31. Keep adjacent-year dates in
those boundary weeks, preserving continuous Monday-Sunday flow with no blanks,
month blocks, snapping, or layout reset. Calendar years produce 53 or 54 rows.

**Positioning and Navigation:** Initial/rebuilt position remains selected week at
viewport top. Ordinary scrolling reaches January and December boundaries.
Previous/next still shifts selected date by active `2W-6W` page; crossing year
rebuilds full range for destination year. Today keeps existing recenter behavior.

**Performance:** Keep one bounded service query for selected-year week span and
one finite delegate model. No incremental loading, timers, polling, or caching.

**Constraints:** Preserve current week flow, 12-color palette, month labels,
events, busy-row expansion, scrolling, zoom preservation, visible-date tracking,
header behavior, and CalendarWindow control semantics.

**Acceptance:** January 1 and December 31 of selected year are reachable; first
and last rows remain complete Monday-Sunday weeks; selected week opens at top;
arrows and Today recenter correctly within/across years; full range stays bounded;
all existing Month visuals and interactions remain unchanged.

### Stage 3a.6 Execution Plan

**Architecture:** Add one DST-safe `CalendarMath.weekCount(startDate, endDate)`
helper that counts seven-day local-calendar steps. MonthView derives boundary
Mondays from selected year and uses helper for finite model length.

**Constraints:** Modify only calendar math/tests and MonthView range properties.
No visual, event, geometry, state, service, control, or interaction changes.

#### Task 1: Count Local-Calendar Weeks

**Files:** Modify `tests/test-calendar-math.js` and `common/CalendarMath.js`.

**Interface:** `weekCount(startDate, endDate)` returns number of seven-day steps
from inclusive aligned start to exclusive aligned end; returns `0` for empty or
reversed spans.

- [x] Add assertions for two weeks, reversed span `0`, 2026 year span `53`, and
  2012 year span `54`.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`; failed because
  `weekCount` was missing.
- [x] Implement loop using existing `dayStart()` and `addDays(cursor, 7)`; export.
- [x] Rerun test; output was `CalendarMath tests passed`.

#### Task 2: Load Complete Selected Calendar Year

**File:** Modify `ui/MonthView.qml`.

**Interfaces:** `rangeYear = selectedDate.getFullYear()`;
`bufferStart = weekStart(new Date(rangeYear, 0, 1))`;
`bufferEnd = addDays(weekStart(new Date(rangeYear, 11, 31)), 7)`;
`bufferWeeks = weekCount(bufferStart, bufferEnd)`.

- [x] Remove fixed `bufferWeeks: 27` and `anchorWeekIndex: 13` properties.
- [x] Add selected-year start/end/week-count bindings above.
- [x] Keep existing model loop, event query, date positioning, trailing padding,
  and navigation integration unchanged.
- [x] Run both Node suites and `qmllint ui/MonthView.qml`; clean output.
- [x] Request focused review for 53/54-row years, DST, boundary weeks, year
  crossing, selected-date positioning, query bounds, and performance; no issues.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] User manually verifies January/December reachability, complete boundary
  weeks, selected-week start, arrows, Today, scrolling, and `2W-6W` zoom.

## Stage 3a.7: Today Card Outline

**Goal:** Make today's Month View card immediately recognizable beyond existing
red date badge.

**Treatment:** Overlay one transparent Rectangle on today's complete day cell.
Use 2px `Theme.currentTime` border at 90% opacity with 3px radius. Keep existing
red date badge. Border renders over month hue, selected background, neutral grid,
and event layer at cell edges without covering event content.

**Constraints:** Modify only `ui/MonthView.qml`. Reuse existing
`dayColumn.today`; add no state, helper, theme value, model field, geometry,
spacing, or interaction change. Preserve selection, month palette, labels,
events, full-year range, scrolling, and `2W-6W` zoom.

**Acceptance:** Exactly current local date has full red outline; all other cells
have none; outline remains visible when today is selected and at every zoom;
events and labels stay unobscured; row geometry and interactions do not change.

### Stage 3a.7 Execution Plan

**Architecture:** Add one non-layout Rectangle inside existing `dayColumn`
delegate, after content declarations, with `z: 2`. Bind visibility directly to
existing `dayColumn.today`.

**Constraints:** Modify only `ui/MonthView.qml`; no helper, state, model, theme,
geometry, spacing, event, or interaction changes.

#### Task 1: Outline Today Card

**File:** Modify `ui/MonthView.qml`.

- [x] Add transparent full-cell Rectangle with `visible: dayColumn.today`,
  `border.width: 2`, `border.color: Theme.currentTime`, `opacity: 0.9`,
  `radius: 3`, and `z: 2`.
- [x] Keep outline outside event Repeater ownership and inside day delegate so it
  follows dynamic row height without affecting layout.
- [x] Run both Node suites and `qmllint ui/MonthView.qml`; clean output.
- [x] Request focused review for one-cell visibility, stacking, event overlap,
  selection coexistence, dynamic row height, and unchanged interaction; no issues.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] User manually verifies Today outline, selected-state coexistence, event
  readability, dynamic row height, and `2W-6W` zoom.

## Stage 3b: Agenda/Day View

**Goal:** Add a read-only, multi-day agenda that makes ordered events and empty
days easy to scan without recreating Week View.

**Range and Navigation:** Agenda starts at `dayStart(selectedDate)` and contains
14 consecutive local-calendar days. Previous/next moves 14 days. Today starts at
current local day. Switching from Month carries its top-visible date; switching
from Week carries current selected date. Agenda exposes no zoom controls.

**Data:** Query `CalendarService.eventsInRange()` once for complete 14-day span.
Build exactly 14 day groups, including empty groups. Assign each normalized event
once to its local start day and preserve service order: all-day first, then timed
start and uid tie-break. Multi-day cards show their range instead of repeating on
every overlapping day.

**Presentation:** Use one vertically scrollable, two-column list. Fixed-width
date rail shows weekday and date. Right side shows compact calendar-colored event
rows with time, title, and optional location, or muted `No events`. Today uses
existing `Theme.currentTime` language. Day rows expand for event count.

**Composition:** Add dedicated `ui/AgendaView.qml`; extend existing
`ui/CalendarWindow.qml` Loader and segmented controls with Agenda mode. Hide
Week/Month zoom controls while Agenda is active. Keep CalendarWindow responsible
only for shared date, mode, navigation, and composition.

**Constraints:** Reuse CalendarService normalization/filtering and existing Theme.
No duplicated date parsing, subprocess, timer, persistence, event interaction,
details, visibility toggle, edit affordance, or Agenda-specific zoom.

**Acceptance:** Exactly 14 consecutive DST-safe days render; empty days are
explicit; events appear once on start day in consistent order; all-day/timed and
multi-day labels are correct; arrows/Today/view switching preserve valid dates;
Agenda creates no timer/model duplication; Week and Month behavior remain intact.

### Stage 3b Execution Plan

**Architecture:** Put pure day grouping in `common/CalendarMath.js`, rendering in
new `ui/AgendaView.qml`, and shared navigation/composition in
`ui/CalendarWindow.qml`. Agenda consumes one sorted service range and adds no
service state.

**Constraints:** Read-only; no clicks, details, mutation, visibility, timer,
polling, subprocess, persistence, dependency, or Agenda zoom.

#### Task 1: Build 14 Agenda Day Groups

**Files:** Modify `tests/test-calendar-math.js` and `common/CalendarMath.js`.

**Interface:** `buildAgendaDays(events, startDate, dayCount)` returns exactly
`dayCount` objects `{ date, events }`. Dates advance with `addDays`; events are
assigned once when their local start date equals group date; input order and
event objects are preserved; invalid starts and starts outside range are ignored.

- [x] Add failing assertions for 14 consecutive groups across Europe/Paris DST,
  explicit empty groups, preserved all-day/timed input order, one-time multi-day
  assignment, ignored ongoing-before-range event, and source immutability.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`; failed because
  `buildAgendaDays` was missing.
- [x] Implement group creation plus local-start-date assignment using existing
  `dayStart()` and `addDays()`; export function.
- [x] Rerun CalendarMath suite; output was `CalendarMath tests passed`.

#### Task 2: Render Read-Only Agenda

**File:** Create `ui/AgendaView.qml`.

**Interfaces:** Required properties `calendarService`, `selectedDate`, and `now`.
Readonly `rangeStart`, `rangeEnd`, `rangeEvents`, and `days`. No signals or
mutable public state.

- [x] Query `[dayStart(selectedDate), addDays(rangeStart, 14))` once and pass
  sorted result to `buildAgendaDays()`.
- [x] Add clipped vertical Flickable containing 14 expanding day rows.
- [x] Render fixed date rail with weekday/date and current-time-red Today marker.
- [x] Render compact event rows with calendar color, all-day or timed range,
  title, and optional location; multi-day range uses exclusive all-day end
  correctly and never creates another card.
- [x] Render muted `No events` for every empty group.
- [x] Run `qmllint ui/AgendaView.qml`; no diagnostics.

#### Task 3: Integrate Agenda Mode

**File:** Modify `ui/CalendarWindow.qml`.

**Interfaces:** Add `agendaViewComponent`, `showAgenda()`, `Agenda` NavButton,
14-day Agenda navigation branch, and Loader Agenda branch. Existing Week/Month
interfaces remain unchanged.

- [x] Make `showWeek()` copy `monthVisibleDate` only when leaving Month; make
  `showAgenda()` do same before activating Agenda.
- [x] Navigate Agenda by `direction * 14` days and keep Today behavior unchanged.
- [x] Add Agenda component with shared service/date/clock bindings.
- [x] Add selected `Agenda` header button and hide all three zoom controls while
  Agenda is active.
- [x] Route Loader among Week, Month, and Agenda without eager extra instances.
- [x] Run both Node suites and
  `qmllint ui/AgendaView.qml ui/CalendarWindow.qml`; clean output.
- [x] Request focused review for grouping/order, empty days, all-day exclusivity,
  DST, Loader lifecycle, navigation, header width, and Week/Month regressions;
  DST assertion and transient-width findings fixed, rereview passed.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [x] User manually verifies 14 days, empty rows, ordering, multi-day labels,
  vertical scrolling, arrows, Today, view switching, and hidden Agenda zoom.

## Stage 3c: Event Details

**Goal:** Open complete normalized event information from every implemented view
without adding editing behavior or duplicating detail formatting.

**Interaction Contract:** `EventCard`, Week View, Month View, and Agenda View
propagate one `eventActivated(var eventData)` signal. CalendarWindow owns nullable
`selectedEvent`. Clicking any event opens details; close button or outside click
dismisses. Navigation, Today, and view switches clear stale selection.

**Presentation:** Add reusable `ui/EventDetailsPanel.qml`, shown as 380px drawer
on right below 63px header. A dim scrim covers remaining calendar content. Drawer
has close affordance and internal vertical scrolling for long text.

**Content:** Show event color and normalized title; calendar name with `Unknown
calendar` fallback; correct timed/all-day date range with exclusive all-day end;
location or `No location`; description or `No description`; reminder labels or
`No reminders`; and read-only/writable status. Do not expose edit/delete actions.

**Composition:** CalendarWindow passes selected event plus CalendarService to one
details panel. Views only emit activation and retain existing event layout/data.
Drawer is not instantiated while no event is selected.

**Constraints:** No mutation, confirmation, visibility toggle, persistence,
timer, polling, subprocess, backend, service model, or per-view details markup.
Preserve Week, Month, Agenda navigation, zoom, scrolling, and layout behavior.

**Acceptance:** Every visible event opens same drawer; normalized title, time,
calendar, location, description, reminders, and status have safe output; all-day
exclusive end is displayed inclusively; long content scrolls; every dismissal
path clears selection; views and navigation remain stable after repeated opens.

### Stage 3c.1: Month Delayed-Callback Lifecycle Fix

**Root Cause:** MonthView queued `Qt.callLater` closures after selected-date and
zoom changes. Switching Loader source destroyed MonthView before those closures
ran, so they evaluated `root.positionDate` in an invalid QML context.

**Fix:** Replace all global delayed closures with one component-owned, zero-delay,
non-repeating Timer. `schedulePositionDate(date)` stores latest date and restarts
Timer; Loader destruction cancels pending work automatically. Scheduling remains
deferred so models and geometry settle, and repeated requests coalesce.

**Verification:** No `Qt.callLater` remains in calendar QML; CalendarMath and Zoom
tests pass; `qmllint ui/MonthView.qml ui/CalendarWindow.qml` is clean; focused
review found no issues. Runtime view-switch warning reproduction remains pending.

### Stage 3c.2: Header And Legend Cleanup

**Goal:** Simplify header while preserving zoom functionality and moving calendar
identity out of crowded controls.

**Behavior:** Remove all three visible zoom controls. Left-click Today remains
unchanged; right-click Today resets active Week/Month zoom and does nothing in
Agenda. Ctrl+wheel zoom and internal zoom state remain.

**Legend:** Remove header legend and render one compact in-app floating card at
bottom-right. Calendar entries stack vertically. Card sits above view content,
below Event Details overlay, and blocks pointer input from leaking underneath.

**Constraints:** Modify only `ui/CalendarWindow.qml`. Do not remove zoom state or
view zoom methods still used by Ctrl+wheel, Month navigation, or right-click reset.

### Stage 3c.3: Details Modal Input Fix

**Root Cause:** Passive close/outside TapHandlers and immediate details Loader
destruction allowed same pointer sequence to activate event cards underneath,
replacing or reopening details.

**Fix:** Make overlay a full modal MouseArea barrier, make panel/X use exclusive
MouseAreas, defer selected-event clearing through root-owned zero-delay Timer, and
ignore event activation while drawer is open or closing. Overlay boundary now
tracks current header plus divider height; panel guards transient null during
Loader teardown.

**Verification:** CalendarMath/Zoom tests and QML lint pass; focused rereview found
no issues. Runtime X/outside click-through reproduction remains pending.

### Stage 3c.4: Month Tint Contrast

Increase only twelve-month cell background alpha from `0.08` to `0.12`. Preserve
palette, selected-cell override, event colors, month labels, and Today outline.

**Execution:** Modify `ui/MonthView.qml` alpha literal only; run Node suites and
`qmllint ui/MonthView.qml`; manually compare month distinction and event contrast.

### Stage 3c.5: Modern Month Palette And Selection Cleanup

Replace twelve month colors with approved Balanced Spectrum palette: `#60a5fa`,
`#818cf8`, `#a78bfa`, `#e879f9`, `#f472b6`, `#fb7185`, `#fb923c`, `#fbbf24`,
`#a3e635`, `#4ade80`, `#2dd4bf`, `#22d3ee`. Use `0.12` background alpha and full
color month labels. Remove Month View selected-date property, surface override,
opacity override, and selected-only bolding. Keep selectedDate internal for
navigation/view handoff; Today remains sole visible date highlight.

**Execution:** Modify `ui/MonthView.qml` only: replace palette, remove all four
selected-style references, set month tint alpha `0.12`, run Node suites and
`qmllint ui/MonthView.qml`, then manually verify all 12 hues and Today contrast.

### Stage 3c.2 Execution Plan

**File:** Modify `ui/CalendarWindow.qml` only.

- [x] Add `rightClicked` signal to NavButton; accept left/right buttons and
  dispatch without changing existing left-click handlers.
- [x] Bind Today right-click to active Week/Month `resetZoom()` and guard Agenda.
- [x] Delete all three header zoom NavButton instances.
- [x] Delete header calendar Repeater and recreate same model as compact
  bottom-right Rectangle with vertical Column entries, `z: 50`, padding, surface
  background, border, radius, and input barrier.
- [x] Keep Event Details Loader at `z: 100` so drawer covers floating legend.
- [x] Run both Node suites and `qmllint ui/CalendarWindow.qml`; clean output.
- [x] Request focused review for right-click dispatch, left-click regression,
  Agenda guard, removed dead UI, overlay stacking/input, and header layout; no
  issues found.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [ ] User manually verifies Today left/right clicks, Week/Month reset, Agenda
  guard, Ctrl+wheel zoom, removed header controls, and floating legend placement.

### Stage 3c Execution Plan

**Architecture:** `CalendarMath.eventDetails()` produces safe drawer data.
`EventDetailsPanel.qml` formats/render it. Views emit event activation only;
CalendarWindow owns selection and lazy overlay lifecycle.

**Constraints:** Read-only; no edit/delete actions, persistence, service state,
timer, polling, subprocess, backend, visibility behavior, or per-view detail UI.

#### Task 1: Build Safe Detail Data

**Files:** Modify `tests/test-calendar-math.js` and `common/CalendarMath.js`.

**Interface:** `eventDetails(event, calendars)` returns `null` for invalid input,
otherwise `{ title, calendarName, color, location, description, reminders,
allDay, startMs, endMs, displayEndMs, status }`. All-day `displayEndMs` is one
local day before exclusive `endMs`. Reminder labels are `At start time`, singular
or plural minutes, or `Reminder` for malformed entries.

- [x] Add failing tests for unknown calendar, empty title/location/description,
  no reminders, malformed reminder, 0/1/15-minute labels, read-only/writable
  status, all-day exclusive-end conversion across DST, and source immutability.
- [x] Run CalendarMath suite; failed because `eventDetails` was missing.
- [x] Implement minimal safe projection using existing date helpers; export it.
- [x] Rerun CalendarMath suite; output was `CalendarMath tests passed`.

#### Task 2: Create Reusable Details Drawer

**File:** Create `ui/EventDetailsPanel.qml`.

**Interfaces:** Required `eventData` and `calendarService`; signal
`closeRequested()`. Readonly `details = CalendarMath.eventDetails(eventData,
calendarService.calendars)`.

- [x] Render opaque 380px panel with event-color header, title, close button, and
  internal clipped Flickable/Column.
- [x] Format timed and all-day single/multi-day ranges from safe detail data.
- [x] Render calendar, location, description, reminders, and status with all
  specified fallbacks and wrapped/elided text where appropriate.
- [x] Run `qmllint ui/EventDetailsPanel.qml`; no diagnostics.

#### Task 3: Emit Activation From Every View

**Files:** Modify `ui/EventCard.qml`, `ui/WeekView.qml`, `ui/MonthView.qml`, and
`ui/AgendaView.qml`.

**Interface:** Each view exposes `signal eventActivated(var eventData)`.
`EventCard` exposes `signal activated(var eventData)` and emits its `eventData`
from TapHandler.

- [x] Add TapHandler plus activation signal to EventCard and forward both Week
  all-day/timed delegates through Week View.
- [x] Add TapHandler to Month event labels and emit original normalized event.
- [x] Add TapHandler to Agenda event rows and emit original normalized event.
- [x] Run `qmllint` on all four view/card files; no diagnostics.

#### Task 4: Own Drawer Lifecycle In CalendarWindow

**File:** Modify `ui/CalendarWindow.qml`.

**Interfaces:** Nullable `selectedEvent`; functions `showEventDetails(eventData)`
and `closeEventDetails()`; lazy `detailsOverlayComponent` and active Loader.

- [x] Connect all three view `eventActivated` signals to `showEventDetails()`.
- [x] Close details before navigate, Today, or any view switch.
- [x] Add overlay below 63px header: dim outside area closes on tap; lazy 380px
  right panel receives selected event/service and close signal.
- [x] Keep header usable and avoid negative transient widths with clamps.
- [x] Run both Node suites and `qmllint` on every touched QML file.
- [x] Request focused review for safe fallbacks, exclusive all-day end, event
  identity, signal routing, click interception, overlay dismissal, Loader
  lifecycle, long-content geometry, and existing view regressions; malformed
  reminder/text, input barrier, DST fold, width, and source-event findings fixed;
  rereview passed.
- [x] Ask user to choose manual or assistant runtime smoke test.
- [ ] User manually opens details from Week all-day/timed, Month, and Agenda;
  verifies content/fallbacks, long scrolling, outside/close dismissal, and
  navigate/Today/view-switch clearing.

## Stage 3d: Calendar Visibility

**Goal:** Let users hide or restore each calendar from the existing floating
legend, with one service-owned visibility state applied consistently to Week,
Month, and Agenda views.

**Interaction:** Each legend row is clickable. A visible calendar uses its filled
color dot and normal label; a hidden calendar uses a hollow or dimmed dot and
muted label. Every calendar may be hidden, producing normal empty view states.

**Service Contract:** Keep immutable source calendar metadata and expose a
replaceable `calendars` array. Normalize raw events against source metadata so a
visibility change never reparses unchanged event dates. Add
`setCalendarVisible(calendarId, visible)`. For a known calendar and boolean
value, replace that calendar object and the public array so QML bindings receive
a change notification. Unknown IDs, non-boolean values, and unchanged values are
no-ops. `eventsInRange()` remains the only view-facing visibility filter.

**Data Flow:** Legend click calls the service operation. Replacing `calendars`
updates the legend and invalidates each loaded view's existing range query.
`CalendarMath.filterEventsInRange()` excludes hidden calendars, so views require
no visibility state or filtering logic.

**Constraints:** Session-only mocked state. Add no persistence, backend,
subprocess, timer, new model abstraction, per-view toggle logic, or event-detail
behavior. Preserve calendar metadata, normalized events, navigation, zoom, and
event ordering.

**Error Handling:** Reject no user action when hiding the last visible calendar.
Unknown calendar IDs and non-boolean values preserve current state. UI passes
the inverse of current `visible` state.

**Verification:** Unit coverage checks a valid hide, restoration, unknown ID,
hidden range filtering, and all calendars hidden. QML lint covers service and
window bindings. Manual runtime checks toggle each legend row in Week, Month,
and Agenda; verify immediate consistent removal/restoration, empty views, visual
state, and no click-through into calendar content.

### Stage 3d Execution Plan

**Architecture:** `CalendarMath.withCalendarVisibility()` performs immutable,
tested state replacement. `CalendarService` owns the replaceable public calendar
array and normalizes events only against immutable source metadata. Existing
`eventsInRange()` filtering updates every loaded view. CalendarWindow only sends
toggle intent and renders state.

**Tech Stack:** Quickshell, QML, JavaScript, Node built-in assertions.

**Global Constraints:** Session-only state; no persistence, helper, backend,
subprocess, polling, timer, dependency, per-view filter, or new model abstraction.
Do not access ancestor Git state. Preserve user-edited header and legend layout.

#### Task 1: Reactive Service-Owned Visibility

**Files:**
- Modify: `tests/test-calendar-math.js`
- Modify: `common/CalendarMath.js`
- Modify: `services/CalendarService.qml`

**Interfaces:**
- Produces: `CalendarMath.withCalendarVisibility(calendars, calendarId, visible)`
  returning the original array for invalid/no-op input or a new array containing
  one replaced calendar object.
- Produces: `CalendarService.setCalendarVisible(calendarId, visible)`.
- Preserves: `CalendarService.calendars`, `events`, `calendarById()`, and
  `eventsInRange(start, end)` consumer contracts.

- [x] **Step 1: Add failing immutable-state tests**

  Add after the shared `calendars` fixture in `tests/test-calendar-math.js`:

  ```js
  {
      const source = calendars.slice(0, 2)
      const before = JSON.stringify(source)
      const hidden = CalendarMath.withCalendarVisibility(source, "personal", false)

      assert.notStrictEqual(hidden, source)
      assert.strictEqual(hidden[0], source[0])
      assert.notStrictEqual(hidden[1], source[1])
      assert.equal(hidden[1].visible, false)
      assert.equal(JSON.stringify(source), before)

      const restored = CalendarMath.withCalendarVisibility(hidden, "personal", true)
      assert.equal(restored[1].visible, true)
      assert.strictEqual(
          CalendarMath.withCalendarVisibility(restored, "personal", true), restored)
      assert.strictEqual(
          CalendarMath.withCalendarVisibility(restored, "missing", false), restored)
      assert.strictEqual(
          CalendarMath.withCalendarVisibility(restored, "personal", "no"), restored)
  }
  ```

- [x] **Step 2: Run test and confirm RED**

  Run: `TZ=Europe/Paris node tests/test-calendar-math.js`

  Expected: failure because `CalendarMath.withCalendarVisibility` is not a
  function.

- [x] **Step 3: Implement minimal immutable replacement helper**

  Add to `common/CalendarMath.js` and export it:

  ```js
  function withCalendarVisibility(calendars, calendarId, visible) {
      if (!Array.isArray(calendars) || typeof calendarId !== "string"
              || typeof visible !== "boolean")
          return calendars

      const index = calendars.findIndex(calendar => calendar.id === calendarId)
      if (index < 0 || calendars[index].visible === visible)
          return calendars

      return calendars.map((calendar, calendarIndex) => calendarIndex === index
          ? Object.assign({}, calendar, { visible }) : calendar)
  }
  ```

- [x] **Step 4: Run test and confirm GREEN**

  Run: `TZ=Europe/Paris node tests/test-calendar-math.js`

  Expected: `CalendarMath tests passed`.

- [x] **Step 5: Add all-hidden filtering regression**

  Add beside existing `filterEventsInRange()` coverage:

  ```js
  {
      const allHidden = calendars.map(calendar =>
          Object.assign({}, calendar, { visible: false }))
      const visible = CalendarMath.filterEventsInRange([
          { uid: "university", calendarId: "university", startMs: 200, endMs: 300 },
          { uid: "personal", calendarId: "personal", startMs: 200, endMs: 300 }
      ], allHidden, 200, 400)

      assert.deepEqual(visible, [])
  }
  ```

- [x] **Step 6: Run filtering regression**

  Run: `TZ=Europe/Paris node tests/test-calendar-math.js`

  Expected: `CalendarMath tests passed`; this confirms existing service-boundary
  filtering already supports the approved empty state and needs no view changes.

- [x] **Step 7: Make CalendarService state reactive without reparsing events**

  In `services/CalendarService.qml`, rename initial calendar literal to immutable
  source metadata and expose a replaceable public array:

  ```qml
  readonly property var sourceCalendars: [
      {
          id: "edt_unistra",
          name: "University",
          color: "#7b9acc",
          writable: false,
          visible: true
      },
      {
          id: "personal",
          name: "Personal",
          color: "#b58bc8",
          writable: true,
          visible: true
      }
  ]
  property var calendars: sourceCalendars
  ```

  Change event normalization to use `root.sourceCalendars`, leaving range
  filtering on `root.calendars`:

  ```qml
  const result = CalendarMath.normalizeEvent(event, root.sourceCalendars)
  ```

  Add service mutation boundary:

  ```qml
  function setCalendarVisible(calendarId, visible) {
      const calendars = CalendarMath.withCalendarVisibility(
          root.calendars, calendarId, visible)
      if (calendars !== root.calendars)
          root.calendars = calendars;
  }
  ```

- [x] **Step 8: Statically verify service implementation**

  Run: `qmllint services/CalendarService.qml`

  Expected: no diagnostics.

#### Task 2: Clickable Legend State

**Files:**
- Modify: `ui/CalendarWindow.qml:321-343`

**Interfaces:**
- Consumes: `calendarService.calendars[*].visible`.
- Consumes: `calendarService.setCalendarVisible(calendarId, visible)`.
- Preserves: floating legend location, dimensions, stacking, and parent input
  barrier.

- [x] **Step 1: Convert each passive legend row into a toggle target**

  Wrap the existing content Row in an Item delegate. Keep dot/text inside Row and
  place the anchored MouseArea on the wrapper so the positioner receives no
  anchored direct child:

  ```qml
  delegate: Item {
      id: calendarEntry

      required property var modelData

      width: calendarRow.implicitWidth
      height: calendarRow.implicitHeight

      Row {
          id: calendarRow

          spacing: 7

          Rectangle {
              width: 8
              height: 8
              radius: 4
              anchors.verticalCenter: parent.verticalCenter
              color: calendarEntry.modelData.visible
                  ? calendarEntry.modelData.color : "transparent"
              border.width: calendarEntry.modelData.visible ? 0 : 1
              border.color: calendarEntry.modelData.color
          }

          Text {
              text: calendarEntry.modelData.name
              color: Theme.textMuted
              opacity: calendarEntry.modelData.visible || rowMouse.containsMouse
                  ? 1 : 0.5
              font.pixelSize: 11
          }
      }

      MouseArea {
          id: rowMouse

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.calendarService.setCalendarVisible(
              calendarEntry.modelData.id, !calendarEntry.modelData.visible)
      }
  }
  ```

- [x] **Step 2: Run complete static verification**

  Run:

  ```bash
  TZ=Europe/Paris node tests/test-calendar-math.js
  node tests/test-zoom.js
  qmllint services/CalendarService.qml ui/CalendarWindow.qml
  ```

  Expected: both Node success messages and no QML diagnostics.

- [x] **Step 3: Request runtime smoke-test choice**

  Ask whether user will test manually or wants assistant to run only:
  `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar`.

- [x] **Step 4: Verify runtime acceptance**

  In Week, Month, and Agenda, click University and Personal legend rows. Confirm
  immediate event removal/restoration, filled/hollow dots, dim hidden labels,
  all-hidden empty states, preserved navigation/zoom, and no click-through into
  view content.

### Stage 3d.1: Legend Positioner Fix

**Runtime Failure:** QML warned `Cannot specify left, right, horizontalCenter,
fill or centerIn anchors for items inside Row. Row will not function.` Legend
entries disappeared because anchored MouseArea was a direct child of Row.

**Fix:** Use an Item as delegate geometry/input owner. Keep only dot and text in
the nested Row; anchor MouseArea to Item. Calendar state and toggle behavior are
unchanged.

**Verification:** CalendarMath and Zoom suites pass; `qmllint
services/CalendarService.qml ui/CalendarWindow.qml` reports no diagnostics.
Runtime confirmed 2026-09-01: legends render, toggles work, no reported warning.

## Stage 4a: View-Local Event Selection

**Goal:** Make every rendered event card selectable before adding mutation UI,
without carrying selection between Week, Month, or Agenda instances.

**Ownership:** Each view owns a string `selectedEventUid`, initialized to empty,
plus `clearSelection()`. CalendarWindow owns no selection state. Switching Loader
source destroys the old view-local selection, so entering any view always starts
with no selected event.

**Interaction:** Single-clicking an event sets that view's `selectedEventUid`.
Every rendered segment with the same source event UID receives the selected
style. Double-clicking an event selects it and opens the existing shared Event
Details drawer. Clicking blank view content clears selection. Closing Event
Details alone leaves selection intact.

**Navigation:** Previous/next arrows and Today call the active view's
`clearSelection()` before changing dates. View switches also clear before Loader
replacement, though destruction remains the reset guarantee. Zooming and
scrolling do not clear selection while the selected event remains represented.

**Presentation:** Add `Theme.selection` with mint `#6ee7b7`. Selected event cards
use a translucent `0.22` mint fill plus solid mint border and left ribbon. Do not
change card position, size, text, overlap geometry, or Month cell/date styling.
All segments of a multi-day event highlight together within the active view.

**Component Contract:** `EventCard` gains required boolean `selected` and signal
`selectionRequested(var eventData)` while retaining
`activated(var eventData)`. Week forwards both signals. Month and Agenda direct
delegates apply the same UID comparison and single/double-click behavior.

**Input Rules:** Only normalized events with non-empty stable UID may become
selected. Event handlers consume card clicks so a card click never triggers the
blank-content clear action. Blank clicks do not open Event Details.

**Constraints:** Add no mutation, editor, creation gesture, delete confirmation,
persistence, service state, timer, backend, subprocess, dependency, keyboard
shortcut, or cross-view selection controller. Preserve existing details modal,
navigation, zoom, scrolling, visibility filtering, and user-edited layout.

**Verification:** Run CalendarMath and Zoom suites and QML lint on every changed
view/card/window file. Manually verify single selection, replacement selection,
same-UID multi-day highlighting, blank clearing, double-click details, details
close retention, navigation clearing, tab reset in both directions, and unchanged
event geometry across Week, Month, and Agenda.

**Deferred Stage 4b Decisions:** Creation uses both header New and empty-space
double-click. Week preselects clicked half-hour for a one-hour timed event;
Month/Agenda preselect clicked all-day date; header New uses selected date at
09:00. Editor fields are title, writable calendar, all-day, start/end, location,
and description. Writable Event Details exposes Edit/Delete; deletion confirms
inline. Reminders remain Stage 5.

### Stage 4a Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development or superpowers:executing-plans to
> implement task-by-task. Checkboxes track execution.

**Goal:** Add single-click event selection and double-click Event Details with
selection reset whenever users navigate or switch views.

**Architecture:** Each loaded view owns one `selectedEventUid`; EventCard and
direct Month/Agenda delegates compare source-event UID to that value. Background
MouseAreas clear selection. CalendarWindow invokes the common
`clearSelection()` view contract before navigation; Loader replacement remains
the cross-view reset guarantee.

**Tech Stack:** Quickshell, QML, JavaScript, existing Node assertion suites.

**Global Constraints:** No mutation, editor, creation gesture, persistence,
service state, timer, backend, subprocess, dependency, or cross-view selection
controller. Preserve event geometry, colors, navigation, zoom, scrolling,
visibility filtering, modal details lifecycle, and user-edited layout. Do not
access ancestor Git state; omit commit steps.

#### Task 1: Selectable EventCard Primitive

**Files:**
- Modify: `common/Theme.js`
- Modify: `ui/EventCard.qml`

**Interfaces:**
- Consumes: required `eventData` and new required boolean `selected`.
- Produces: `selectionRequested(var eventData)` on single-click.
- Preserves: `activated(var eventData)`, now emitted only on double-click.
- Source identity: use `eventData.sourceEvent ?? eventData` for both signals.

- [x] **Step 1: Record current failing interaction**

  Runtime baseline: a single click immediately opens Event Details and no card
  has a selected outline. This fails approved single-select/double-open behavior.

- [x] **Step 2: Add selection contract and full-card fill**

  Add shared color to `common/Theme.js`:

  ```js
  var selection = "#6ee7b7"
  ```

  Add property/signal beside existing EventCard contract and update fill
  bindings so fill, border, and ribbon all use selection color:

  ```qml
  required property bool selected
  property color selectionColor: Theme.selection

  signal selectionRequested(var eventData)
  signal activated(var eventData)

  color: root.selected
      ? Qt.rgba(root.selectionColor.r, root.selectionColor.g,
          root.selectionColor.b, 0.22)
      : Qt.rgba(root.eventColor.r, root.eventColor.g, root.eventColor.b, 0.2)
  border.width: 1
  border.color: root.selected ? root.selectionColor
      : Qt.rgba(root.eventColor.r, root.eventColor.g, root.eventColor.b, 0.65)
  ```

  Bind EventCard's left ribbon to:

  ```qml
  color: root.selected ? root.selectionColor : root.eventColor
  ```

- [x] **Step 3: Replace passive handlers with exclusive click handling**

  Replace EventCard HoverHandler and TapHandler with:

  ```qml
  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
          const event = root.eventData.sourceEvent ?? root.eventData;
          root.selectionRequested(event);
      }
      onDoubleClicked: {
          const event = root.eventData.sourceEvent ?? root.eventData;
          root.selectionRequested(event);
          root.activated(event);
      }
  }
  ```

- [x] **Step 4: Verify EventCard syntax**

  Run: `qmllint ui/EventCard.qml`

  Expected: no diagnostics.

#### Task 2: View-Local Selection In Week, Month, And Agenda

**Files:**
- Modify: `ui/WeekView.qml`
- Modify: `ui/MonthView.qml`
- Modify: `ui/AgendaView.qml`

**Interfaces:**
- Each view produces: writable `property string selectedEventUid: ""` and
  `function clearSelection()`.
- Each view consumes: normalized event objects with stable non-empty `uid`.
- Each view preserves: `eventActivated(var eventData)` for double-click details.

- [x] **Step 1: Add shared view-local contract to all three views**

  Add this property/function to WeekView, MonthView, and AgendaView:

  ```qml
  property string selectedEventUid: ""

  function clearSelection() {
      root.selectedEventUid = "";
  }

  function selectEvent(eventData) {
      if (eventData && typeof eventData.uid === "string"
              && eventData.uid.length > 0)
          root.selectedEventUid = eventData.uid;
  }
  ```

- [x] **Step 2: Wire both Week EventCard delegates**

  In Week all-day and timed EventCard delegates, bind source UID and forward
  selection before existing activation:

  ```qml
  selected: root.selectedEventUid
      === (modelData.sourceEvent ?? modelData).uid
  onSelectionRequested: event => root.selectEvent(event)
  onActivated: event => root.eventActivated(event)
  ```

- [x] **Step 3: Add Week blank-content clearing**

  Add a left-button MouseArea before the all-day Repeater inside its Rectangle:

  ```qml
  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: root.clearSelection()
  }
  ```

  Add the same MouseArea as first child of the timed grid content Item at
  `WeekView.qml:230`. EventCard delegates remain later siblings and consume card
  clicks; dragging the Flickable cancels background clicks.

- [x] **Step 4: Add Month UID selection styling and tap split**

  In Month event delegate, change border and replace HoverHandler/TapHandler:

  ```qml
  readonly property var sourceEvent: modelData.sourceEvent ?? modelData
  readonly property bool selected:
      root.selectedEventUid === sourceEvent.uid
  readonly property color selectionColor: Theme.selection

  color: selected
      ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.22)
      : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.23)
  border.width: 1
  border.color: selected ? selectionColor
      : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.58)

  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selectEvent(monthEvent.sourceEvent)
      onDoubleClicked: {
          root.selectEvent(monthEvent.sourceEvent);
          root.eventActivated(monthEvent.sourceEvent);
      }
  }
  ```

- [x] **Step 5: Add Month blank-cell clearing**

  Add this MouseArea inside each `dayColumn`, after cell grid/background visuals
  and before event Repeater:

  ```qml
  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: root.clearSelection()
  }
  ```

  Keep event delegates declared after it so card input wins. Keep Today outline
  non-interactive at `z: 2`.

- [x] **Step 6: Add Agenda UID selection styling and tap split**

  In Agenda event delegate, change border and replace HoverHandler/TapHandler:

  ```qml
  readonly property bool selected:
      root.selectedEventUid === modelData.uid
  readonly property color selectionColor: Theme.selection

  color: selected
      ? Qt.rgba(selectionColor.r, selectionColor.g, selectionColor.b, 0.22)
      : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.16)
  border.width: 1
  border.color: selected ? selectionColor
      : Qt.rgba(eventColor.r, eventColor.g, eventColor.b, 0.52)

  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selectEvent(agendaEvent.modelData)
      onDoubleClicked: {
          root.selectEvent(agendaEvent.modelData);
          root.eventActivated(agendaEvent.modelData);
      }
  }
  ```

  Bind Agenda's left ribbon to:

  ```qml
  color: agendaEvent.selected ? agendaEvent.selectionColor
      : agendaEvent.eventColor
  ```

- [x] **Step 7: Add Agenda blank-row clearing**

  Add this MouseArea inside each `dayRow`, after backgrounds/divider and before
  `dateRail` and `eventColumn`:

  ```qml
  MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: root.clearSelection()
  }
  ```

  Later event delegates consume card clicks; date rail and `No events` areas
  remain blank-selection targets.

- [x] **Step 8: Verify all view syntax**

  Run:

  ```bash
  qmllint ui/EventCard.qml ui/WeekView.qml ui/MonthView.qml ui/AgendaView.qml
  ```

  Expected: no diagnostics.

#### Task 3: Navigation Reset And Complete Verification

**Files:**
- Modify: `ui/CalendarWindow.qml:75-113`
- Verify: all changed Stage 4a QML and existing Node suites.

**Interfaces:**
- Consumes: active Loader item `clearSelection()` implemented identically by
  WeekView, MonthView, and AgendaView.
- Preserves: details close behavior and all date/view transitions.

- [x] **Step 1: Add active-view clearing helper**

  Add before `navigate(direction)`:

  ```qml
  function clearViewSelection() {
      if (viewLoader.item)
          viewLoader.item.clearSelection();
  }
  ```

- [x] **Step 2: Clear before every navigation path**

  Call `root.clearViewSelection();` immediately before
  `root.closeEventDetails();` in `navigate()`, `goToday()`, `showWeek()`,
  `showMonth()`, and `showAgenda()`. Do not change their existing date handoff or
  current-view assignments.

- [x] **Step 3: Run complete static gate**

  Run:

  ```bash
  TZ=Europe/Paris node tests/test-calendar-math.js
  node tests/test-zoom.js
  qmllint ui/EventCard.qml ui/WeekView.qml ui/MonthView.qml ui/AgendaView.qml ui/CalendarWindow.qml
  ```

  Expected: `CalendarMath tests passed`, `Zoom tests passed`, and no QML
  diagnostics.

- [x] **Step 4: Request runtime smoke-test choice**

  Ask whether user will test manually or wants assistant to run only:
  `quickshell -c /home/Zrabbit/Documents/Dotfiles/ArchLinux/QuickShell/.config/quickshell/calendar`.

- [x] **Step 5: Verify runtime acceptance**

  In Week, Month, and Agenda verify: single-click selects; a second event replaces
  selection; every segment sharing UID highlights; blank click clears;
  double-click opens details; closing details retains selection; arrows and Today
  clear; switching each view and returning starts unselected; zoom/scroll preserve
  selection; event geometry and runtime output remain clean.

## Stage 4b: Mocked Event Mutations

**Goal:** Add session-only event creation, editing, and deletion through tested
CalendarService operations and one shared right-side editor.

**Structure:** Create `common/EventMutation.js` for event normalization,
field-specific validation, permission checks, and immutable raw-event array
transforms. Move existing `normalizeEvent()` and its focused tests out of
CalendarMath into this module; no view consumes that API. CalendarMath remains
date/layout/detail logic. Create one `ui/EventEditorPanel.qml`; keep its repeated
field chrome as local inline components rather than adding one-file wrappers.

**Service Contract:** Make `rawEvents` replaceable. CalendarService remains sole
mutable state owner and exposes `createEvent(eventData)`,
`updateEvent(uid, eventData)`, and `deleteEvent(uid)`. Successful create/update
returns `{ ok: true, event }`; delete returns `{ ok: true, uid }`. Failure returns
`{ ok: false, field, message }` and preserves raw/events arrays exactly.

**Validation And Permissions:** Create generates a collision-free session UID.
Create/update require a known writable destination calendar. Update/delete
require a known event whose normalized `readOnly` is false. Update preserves UID
and fields excluded from the editor, including reminders. Empty title normalizes
to `Untitled`; location/description normalize to empty strings. All-day values
must be valid local `YYYY-MM-DD` dates with exclusive service end; timed values
must be ISO strings with explicit offset. Every end must be later than start.
Missing IDs, malformed dates/times, unknown records, and read-only targets return
one stable field/message result. Generated create UIDs skip collisions internally.

**Editor:** `EventEditorPanel.qml` imports bundled Qt Quick Controls and is styled
with local Theme values. It supports create/edit mode and fields for title,
writable calendar, all-day, start/end date, timed start/end time, location, and
description. Date text is `YYYY-MM-DD`; time text is `HH:mm`. All-day end is
inclusive in UI and converted to/from exclusive service storage. Reminders and
event color are not editable.

**Editor Errors:** Local format checks and authoritative service errors both mark
one exact field, show one message, preserve every entered value, and focus the
invalid field. Cancel never calls service. Successful create/edit closes editor
and opens Event Details for returned normalized event.

**Overlay Flow:** CalendarWindow owns nullable `editorRequest` in addition to
`selectedEvent`. Existing modal overlay loads editor when `editorRequest` exists,
otherwise details. Edit cancel returns to the same details event; create cancel
closes overlay. Save replaces editor with returned details without exposing a
click-through frame. Navigation/view switching closes either panel and preserves
existing deferred teardown safety.

**Details Actions:** Writable Event Details shows Edit and Delete; read-only
events show neither. Delete first reveals inline Cancel/Delete permanently
confirmation. Cancel leaves service and selection unchanged. Successful delete
closes overlay and clears active-view selection. Failed delete remains open and
shows service message.

**Creation Entry Points:** Add header New beside Today, enabled only when a
writable calendar exists. It opens a one-hour timed draft on selected date from
09:00 to 10:00. Each view adds `createRequested(var defaults)`. Blank
double-click in Week timed grid uses the clicked whole-hour block
and creates a one-hour draft; Week all-day strip, Month day, and Agenda day open
an all-day draft for clicked date. Existing single blank click still only clears
selection. Card MouseAreas consume double-clicks, so details and creation cannot
both open.

**State Updates:** Every successful operation replaces `rawEvents`, causing one
events binding refresh. Week, Month, and Agenda continue reading only
`eventsInRange()`, so no view duplicates mutation, validation, or filtering.
Creating in a hidden writable calendar succeeds but remains filtered until that
calendar is shown.

**Implementation Checkpoints:**

1. Pure mutation module plus CalendarService operations and automated tests.
2. Shared editor plus header New/create flow.
3. Writable details Edit/Delete with inline confirmation.
4. Contextual blank double-click creation in Week, Month, and Agenda.

Each checkpoint receives static verification and a separate manual runtime test
before continuing.

**Constraints:** No persistence, ICS writing, native helper, transport,
recurrence, reminders UI, notification scheduling, undo, drag/drop, event color
editing, account management, new daemon, polling, or extra timer. Preserve Stage
4a selection, calendar visibility, navigation, zoom, details modal safety, and
user-modified card ribbons/layout.

**Acceptance:** Create/edit/delete update all views immediately; save opens
normalized details; cancellations preserve state; invalid fields preserve form
input; direct read-only/invalid service calls fail without state changes; delete
requires explicit confirmation; contextual defaults match each view; restarting
the config restores original mock fixtures.

### Stage 4b.1: Calendar ComboBox Styling

**Goal:** Make closed calendar field and dropdown menu visually match other editor
fields without changing calendar data or selection behavior.

**Design:** Keep native Controls.ComboBox behavior but replace its contentItem,
indicator, delegate, popup content, and popup background. Closed field and popup
use Theme.background, Theme.border, Theme.radius, editor font, and matching text
padding. Popup width equals field width; text-only rows use Theme.surfaceRaised on
hover/current selection and clip within rounded popup bounds.

**Constraints:** Modify only calendarCombo in `ui/EventEditorPanel.qml`. Preserve
writable calendar filtering, currentIndex, onActivated, validation border, editor
layout, and user typography/spacing changes. Add no reusable component for this
single control.

**Verification:** QML lint plus manual checks for closed-field alignment, popup
background/border/radius, row hover/selection, opening/closing, and Personal
selection. Test again when multiple writable mock calendars exist.

#### Stage 4b.1 Execution Plan

**File:** Modify only `ui/EventEditorPanel.qml` calendarCombo.

- [x] Replace default contentItem with padded Text bound to `displayText` and
  ComboBox font/color.
- [x] Replace indicator with one right-aligned down-chevron Text.
- [x] Replace delegate with 34px text-only ItemDelegate using Theme text and
  surfaceRaised hover/current background.
- [x] Replace popup with width-matched Popup/ListView using 4px padding,
  Theme.background, one-pixel Theme.border, Theme.radius, clipping, and vertical
  ScrollIndicator.
- [x] Preserve model, textRole, valueRole, currentIndex, onActivated, and invalid
  border binding exactly.
- [x] Run `qmllint ui/EventEditorPanel.qml`; manually verify popup and selection.

### Stage 4b.2: Date And Time Wheel Pickers

**Goal:** Replace editable date text with centered vertical date wheels and add
optional wheel selection to still-editable time fields.

**Structure:** Create `ui/DateTimeWheelPopup.qml` using native Controls.Tumbler.
It supports date mode with year/month/day wheels and time mode with hour/minute
wheels. EventEditorPanel owns one popup instance and target-field routing; service
serialization and validation remain unchanged.

**Date Interaction:** Date fields are read-only picker surfaces styled exactly
like FormField. Clicking anywhere opens date mode. Year spans current year ±100;
month shows names; day model follows selected year/month and leap years. Current
values are centered. Done applies all three values; outside click or Escape
cancels without changing fields. Day clamps to last valid day after year/month
changes.

**Time Interaction:** Time fields remain freely editable when clicking their text
area. A dedicated trailing expand button opens time mode. Hour offers 00-23;
minute offers 00-55 in five-minute steps. Picker initialization rounds a valid
typed minute to nearest five only inside popup; field changes only after Done.
Typed values continue accepting every valid `HH:mm` minute.

**Defaults:** Header New uses today's local date at 09:00-10:00. Edit mode keeps
event dates. Future contextual creation keeps clicked date/time defaults.

**Presentation:** Popup matches editor field background, border, radius, font,
and spacing. Five rows are visible per wheel; center row uses Theme.text and a
subtle Theme.surfaceRaised highlight, adjacent rows use Theme.textMuted. Date
mode labels columns YEAR/MONTH/DAY; time mode labels HOUR/MINUTE.

**Constraints:** Preserve all user changes in EventEditorPanel, including label
insets, typography, All-Day toggle, error placement, footer button order, and
calendar ComboBox. Add no new date/time dependency, timer, or service format.

**Verification:** QML lint both files. Manually test leap years, month day clamps,
today default, picker cancel/Done, direct time typing, five-minute wheel values,
start/end routing, all-day hidden times, edit initialization, and invalid range
errors after picker selection.

#### Stage 4b.2 Execution Plan

**Files:**
- Create: `ui/DateTimeWheelPopup.qml`
- Modify: `common/CalendarMath.js`
- Modify: `tests/test-calendar-math.js`
- Modify: `ui/EventEditorPanel.qml`
- Modify: `ui/CalendarWindow.qml`

**Interfaces:**
- `CalendarMath.daysInMonth(year, monthIndex)` returns 28-31.
- `CalendarMath.roundMinuteToStep(minute, step)` returns nearest valid step,
  clamped below 60.
- DateTimeWheelPopup exposes `showDate(target, date)`,
  `showTime(target, text)`, `dateAccepted(target, year, month, day)`, and
  `timeAccepted(target, hour, minute)`.

- [x] Add failing CalendarMath tests for leap/non-leap February, 30/31-day
  months, and five-minute rounding at 0, 12, 13, 58.
- [x] Run `TZ=Europe/Paris node tests/test-calendar-math.js`; confirm missing
  helper failure.
- [x] Implement/export `daysInMonth()` with local Date construction and
  `roundMinuteToStep()` with finite-value validation and `0..60-step` clamping.
- [x] Rerun CalendarMath suite; expect `CalendarMath tests passed`.
- [x] Create DateTimeWheelPopup as styled Controls.Popup with modal outside/Escape
  cancellation, date/time modes, five visible rows per Controls.Tumbler, centered
  surfaceRaised highlight, YEAR/MONTH/DAY or HOUR/MINUTE labels, Cancel and Done.
- [x] Build year model from current year ±100, month-name model, dynamic day
  model, hour `00..23`, and minute `00..55` by five. Clamp selected day whenever
  year/month wheel changes. Keep popup draft state isolated until Done.
- [x] Add local PickerField to EventEditorPanel for read-only date surfaces. Add
  optional picker button/signal to FormField while leaving its text area editable.
- [x] Replace start/end date FormFields with PickerFields; add picker buttons to
  both time FormFields; route one DateTimeWheelPopup by `start`/`end` target and
  update only matching draft text after accepted signal.
- [x] Change CalendarWindow headerCreateDefaults to local today at 09:00-10:00;
  leave future contextual defaults untouched.
- [x] Run CalendarMath, EventMutation, and Zoom suites plus
  `qmllint ui/DateTimeWheelPopup.qml ui/EventEditorPanel.qml ui/CalendarWindow.qml`.
- [x] Popup acceptance superseded by approved Stage 4b.2.2 inline redesign.

### Deferred UI Requests

**Dynamic Selection Highlight:** Replace fixed mint selection with a brighter
variant derived from each event card's own color, applied consistently to card
background, border, and ribbon in Week, Month, and Agenda. Design brightness and
contrast rules before implementation; do not change during Stage 4b.2.

**Centered Event Editor:** Replace right-side editor drawer presentation with a
dead-center floating modal panel while preserving details routing, scrim,
validation, responsive sizing, and deferred click-through-safe teardown. Design
separately after current mutation checkpoints; do not move Event Details unless
explicitly requested.

**Final Layout Syntax Migration:** Replaced all remaining `Row` and `Column`
positioners with `RowLayout` and `ColumnLayout`; no `Grid` positioners remained.
Preserved geometry and behavior through explicit `Layout.*` sizing, alignment,
margins, and spacing.

- [x] Convert eight positioners across CalendarWindow, WeekView,
  EventEditorPanel, EventCard, and AgendaView.
- [x] Confirm zero `Row`, `Column`, or `Grid` declarations; run targeted QML
  lint and all Node suites; complete targeted code review.
- [ ] Manually verify Week, Agenda, editor scrolling, event cards, and legend.

### Stage 4b.2.1: Tumbler Delegate And Initial Position Fix

**Root Causes:** WheelText consumed Controls.Tumbler.displacement without required
delegate `index`, producing one warning per item. Persistent hidden Tumblers also
animated from their previous currentIndex whenever showDate/showTime assigned new
indexes immediately before opening.

**Fix:** Declare required `index` on WheelText. Load date/time wheel groups only
while popup is visible, after draft values are set; each fresh Tumbler receives
its currentIndex during construction and opens already centered without catch-up
scrolling. Preserve normal user flick/snap behavior.

**Verification:** All three Node suites pass and QML lint is clean. Runtime warning
and no-opening-scroll confirmation remain pending.

### Stage 4b.2.2: Inline Five-Field Wheel Redesign

**Status:** Approved. Supersedes Stage 4b.2 popup presentation and removes
`ui/DateTimeWheelPopup.qml` after replacement.

**Goal:** Render START and END as five compact fields: YEAR, MONTH, DAY, HOUR,
and MINUTE, with one inline wheel expanded at a time.

**Structure:** Create `ui/InlineWheelField.qml`. It supports picker-only mode for
date parts and editable mode for time parts. EventEditorPanel owns one
`expandedField` string and all start/end date-time values; no popup state remains.

**Collapsed Layout:** START and END each display five horizontally aligned fields
with small YEAR/MONTH/DAY/HOUR/MIN labels. All-Day hides HOUR and MINUTE. Year and
day show numbers; month shows its name. Hour/minute are separate two-digit text
inputs. Existing service serialization remains date `YYYY-MM-DD` plus time
`HH:mm`.

**Expansion:** Clicking a date field expands its wheel. Clicking only the trailing
button of an hour/minute field expands its wheel; clicking its body edits text.
Opening one field collapses any other. Expanded height shows exactly five rows:
two previous, selected center, two next. A trailing up-chevron collapses the
active wheel. Expansion participates in Column layout and pushes later content;
other fields align vertically with the selected center row.

**Selection:** Wheel center changes update editor state immediately. Year spans
current year ±100. Month uses full names. Day model follows selected year/month
and clamps to the final valid day, including leap years. Hour uses 00-23; minute
wheel uses 00-55 in five-minute steps. Opening an editable minute wheel rounds its
current valid text to nearest five; direct typed values may use any minute until
existing save validation.

**Defaults And Validation:** Header New remains today at 09:00-10:00. Edit mode
loads event values. Future contextual creation keeps clicked defaults. Existing
inclusive all-day end conversion, invalid-range errors, field preservation, and
service format remain unchanged.

**Presentation:** InlineWheelField uses Theme.background, Theme.border,
Theme.radius, Theme.font/Theme.fontMono, and the editor's current 34px collapsed
height. Selected center row uses Theme.surfaceRaised and Theme.text; adjacent
rows use Theme.textMuted. Preserve user label inset, typography, All-Day toggle,
error position, ComboBox, footer order, and spacing outside START/END controls.

**Verification:** Delete popup references/file, run all three Node suites and QML
lint. Manually verify one-at-a-time expansion, five visible entries, immediate
selection, time text editing versus button expansion, all-day hiding, leap/day
clamp, start/end independence, create/edit initialization, and save validation.

### Stage 4b.2.3: Field-Anchored Wheel Overlay

**Root Cause:** InlineWheelField increased its own height from 48px to 164px and
EventEditorPanel propagated `rowExpanded` to every sibling. Row/Column layout
therefore shifted the entire field row and all later form content downward.

**Correction:** Keep every field at fixed label-plus-34px height. Render expanded
five-row Tumbler in a non-modal Controls.Popup anchored to that field. Popup width
matches field; its center row overlays the collapsed cell while two rows extend
above and two below. Use same Theme background, border, and radius. Popup covers
neighboring content and never participates in Row/Column geometry.

**Input:** Date field body opens popup; time input remains editable and only its
trailing chevron opens popup. Popup closes on outside press, Escape, explicit
collapse, or another field opening. `onClosed` clears EventEditorPanel's shared
expandedField state. Selection remains immediate.

**Constraints:** Remove `rowExpanded`, expanded-height alignment, and layout push
logic only. Preserve models, date/time state helpers, service serialization,
all-day visibility, user editor styling, and one-expanded-field rule.

**Verification:** QML lint plus manual checks for unchanged cell position, exact
center-row alignment, two rows above/below, popup stacking, outside-click closure,
time body editing, one-at-a-time opening, and no runtime warnings.

### Header Current View Emphasis

**Design:** Text-only NavButton uses Theme.accent when selected,
Theme.text for inactive hover, and Theme.textMuted otherwise. Existing view
bindings, transparent button backgrounds, dimensions, Japanese labels, and user
header layout remain unchanged.

**Execution:** Modify only NavButton Text color binding in
`ui/CalendarWindow.qml`; run QML lint and manually switch Week/Month/Agenda.

### Stage 4b.2.4: Overlay Coordinate Timing Fix

**Root Cause:** Popup x/y bindings called `mapToItem()` during component startup.
Ancestor Row/Column/Flickable geometry is not tracked as a binding dependency, so
coordinates stayed at their pre-layout values near the window top.

**Fix:** Compute overlay coordinates once inside `onExpandedChanged`, immediately
before `open()`, when field layout is settled. Keep center-row offset unchanged.

**Verification:** All Node suites and QML lint pass; runtime position confirmed.

### Stage 4b.2.5: Bounded Day Wheel Trial

**Design:** DAY popup shows selected value plus at most two neighboring values.
When both sides are available, selected value stays centered with one value above
and one below. First value sits at top with two later values; final value sits at
bottom with two earlier values. Never add blank or wrapping entries. DAY runtime
approval extends this behavior to YEAR, MONTH, HOUR, and MINUTE.

**Verification:** Check day 1, day 2, a middle day, penultimate day, and final day
in both START and END. Confirm three-row maximum, centered middle selections,
boundary cropping, field alignment, scrolling, and no runtime warnings. Recompute
popup overlay coordinates whenever scrolling changes the number of rows above;
the selected row must remain anchored over the original collapsed field.

### Stage 4b.2.6: Full-Width Date-Time Rows

**Design:** START and END use `RowLayout` across the same content width as other
form fields. With `420px` available and four `4px` gaps, timed fields use
YEAR/MONTH/DAY/HOUR/MINUTE preferred widths `75/106/54/85/84`. Every field fills
proportionally when panel width changes. All-Day redistributes full width among
its three visible date fields using the existing `100/140/100` ratio.

#### Stage 4b.2.3 Execution Plan

- [x] Keep InlineWheelField fixed at labelHeight + collapsedHeight; remove
  rowExpanded and all expanded-height geometry.
- [x] Replace inline Loader/collapse button with non-modal Controls.Popup parented
  to field, width-matched, 170px high, and positioned at collapsed field y minus
  two 34px rows.
- [x] Style Popup background exactly like collapsed field. Load one five-row
  Tumbler only while visible; center highlight overlays original cell.
- [x] Bind expanded true/false to Popup open/close. On outside/Escape closure emit
  collapseRequested so EventEditorPanel clears expandedField.
- [x] Remove startParts/endParts expanded properties, every rowExpanded binding,
  and obsolete rowExpanded helper. Preserve expansionRequested and selection
  handlers.
- [x] Run all three Node suites and QML lint; manually verify Stage 4b.2.3.

#### Stage 4b.2.2 Execution Plan

**Files:**
- Create: `ui/InlineWheelField.qml`
- Modify: `ui/EventEditorPanel.qml`
- Delete: `ui/DateTimeWheelPopup.qml`

**Interfaces:** InlineWheelField receives `label`, `model`, `currentIndex`,
`displayText`, `editable`, `text`, `expanded`, `rowExpanded`, and `invalid`.
It emits `expansionRequested()`, `selectionRequested(index, value)`, and
`textEdited(text)`.

- [x] Create InlineWheelField with 34px collapsed field, 14px part label, and
  150px five-row Tumbler when expanded. Require delegate index/modelData for
  Tumbler displacement styling.
- [x] In picker-only mode, clicking collapsed field requests expansion. In
  editable mode, text body remains a TextField and only trailing chevron requests
  expansion. Expanded mode includes a centered collapse chevron.
- [x] Add EventEditorPanel `expandedField`, year/month/hour/minute models, and
  helpers to read/update one date or time part while retaining existing
  `startDateText`, `endDateText`, `startTimeText`, and `endTimeText` serialization.
- [x] Clamp day after year/month selection using CalendarMath.daysInMonth. Round
  minute to nearest five only when opening its wheel. Opening any field replaces
  `expandedField`; collapse sets it empty.
- [x] Replace each START/END Row with YEAR/MONTH/DAY/HOUR/MIN InlineWheelFields.
  Set `rowExpanded` for every sibling so collapsed controls align with expanded
  selected center. Hide HOUR/MIN when All-Day.
- [x] Remove DateTimeWheelPopup instance/functions/import references and delete
  its file. Preserve editor save/load conversion and all unrelated user styling.
- [x] Run all three Node suites and
  `qmllint ui/InlineWheelField.qml ui/EventEditorPanel.qml ui/CalendarWindow.qml`.
- [x] Manually verify Stage 4b.2.2 acceptance before resuming edit/delete.

### Stage 4b Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development or superpowers:executing-plans to
> implement task-by-task. Checkboxes track execution.

**Goal:** Deliver tested session-only create/edit/delete operations, one shared
editor drawer, writable details actions, and contextual creation gestures.

**Architecture:** `EventMutation.js` owns pure event normalization, validation,
permission checks, and immutable raw-array transforms. CalendarService alone
applies successful arrays. EventEditorPanel owns draft/form error state;
CalendarWindow owns editor/details overlay routing. Views only emit contextual
create defaults.

**Tech Stack:** Quickshell, QML, Qt Quick Controls, JavaScript, Node built-in
assertions.

**Global Constraints:** No persistence, ICS writing, helper transport,
recurrence, reminder editing, notifications, undo, drag/drop, event-color editing,
polling, dependency, daemon, or extra timer. Preserve Stage 4a selection,
visibility filtering, navigation, zoom, modal teardown, and user-modified card
ribbons/layout. Do not access ancestor Git state; omit commit steps.

#### Checkpoint 1: Pure Mutation Boundary And CalendarService

**Files:**
- Create: `common/EventMutation.js`
- Create: `tests/test-event-mutation.js`
- Modify: `common/CalendarMath.js`
- Modify: `tests/test-calendar-math.js`
- Modify: `services/CalendarService.qml`

**Interfaces:**
- `EventMutation.normalizeEvent(source, calendars) -> normalized|null`.
- `EventMutation.createEvent(rawEvents, calendars, eventData, uid)`.
- `EventMutation.updateEvent(rawEvents, calendars, uid, eventData)`.
- `EventMutation.deleteEvent(rawEvents, calendars, uid)`.
- Pure successes include `rawEvents`; pure failures are
  `{ ok: false, field, message }` and never mutate input.
- CalendarService public successes omit `rawEvents` and expose only normalized
  event or deleted UID.

- [x] **Step 1: Create failing EventMutation tests**

  Create `tests/test-event-mutation.js` with Node assertions and two calendars:

  ```js
  const assert = require("node:assert/strict")
  const EventMutation = require("../common/EventMutation.js")

  const calendars = [
      { id: "readonly", name: "Read only", color: "#6688aa", writable: false },
      { id: "personal", name: "Personal", color: "#88aa66", writable: true }
  ]
  const rawEvents = [
      {
          uid: "readonly-event", calendarId: "readonly", title: "Lecture",
          start: "2026-09-02T09:00:00+02:00",
          end: "2026-09-02T10:00:00+02:00", allDay: false, reminders: []
      },
      {
          uid: "personal-event", calendarId: "personal", title: "Review",
          start: "2026-09-02T10:00:00+02:00",
          end: "2026-09-02T11:00:00+02:00", allDay: false,
          reminders: [{ minutesBefore: 15 }]
      }
  ]
  const validDraft = {
      calendarId: "personal", title: "New event", description: "Notes",
      location: "Library", start: "2026-09-03T09:00:00+02:00",
      end: "2026-09-03T10:00:00+02:00", allDay: false
  }

  {
      const before = JSON.stringify(rawEvents)
      const result = EventMutation.createEvent(
          rawEvents, calendars, validDraft, "mock-1")
      assert.equal(result.ok, true)
      assert.equal(result.event.uid, "mock-1")
      assert.equal(result.event.readOnly, false)
      assert.equal(result.rawEvents.length, 3)
      assert.equal(JSON.stringify(rawEvents), before)
  }

  assert.deepEqual(EventMutation.createEvent(rawEvents, calendars,
      Object.assign({}, validDraft, { calendarId: "readonly" }), "mock-1"), {
      ok: false, field: "calendarId", message: "Calendar is read-only"
  })
  assert.equal(EventMutation.createEvent(rawEvents, calendars,
      Object.assign({}, validDraft, { end: validDraft.start }), "mock-1").field,
  "end")

  {
      const result = EventMutation.updateEvent(rawEvents, calendars,
          "personal-event", Object.assign({}, validDraft, { title: "Updated" }))
      assert.equal(result.ok, true)
      assert.equal(result.event.uid, "personal-event")
      assert.deepEqual(result.event.reminders, [{ minutesBefore: 15 }])
      assert.equal(result.rawEvents[1].title, "Updated")
  }

  assert.equal(EventMutation.updateEvent(
      rawEvents, calendars, "readonly-event", validDraft).ok, false)
  assert.equal(EventMutation.updateEvent(
      rawEvents, calendars, "missing", validDraft).field, "uid")

  {
      const result = EventMutation.deleteEvent(
          rawEvents, calendars, "personal-event")
      assert.equal(result.ok, true)
      assert.equal(result.uid, "personal-event")
      assert.deepEqual(result.rawEvents.map(event => event.uid), ["readonly-event"])
  }

  assert.equal(EventMutation.deleteEvent(
      rawEvents, calendars, "readonly-event").ok, false)
  assert.equal(EventMutation.deleteEvent(
      rawEvents, calendars, "missing").field, "uid")

  console.log("EventMutation tests passed")
  ```

  Move existing normalize-event cases from `tests/test-calendar-math.js` into
  this file and call `EventMutation.normalizeEvent`; retain all current expected
  read-only, color, timed-offset, all-day, unknown-calendar, and bad-range values.

- [x] **Step 2: Run RED test**

  Run: `TZ=Europe/Paris node tests/test-event-mutation.js`

  Expected: module-not-found for `common/EventMutation.js`.

- [x] **Step 3: Implement field-specific normalization and validation**

  Create `common/EventMutation.js`. Use these exact failure fields/messages:

  ```js
  const errors = {
      event: "Event data is required",
      uid: "Event not found",
      calendarId: "Choose a writable calendar",
      start: "Enter a valid start",
      end: "End must be later than start"
  }

  function failure(field, message) {
      return { ok: false, field, message }
  }
  ```

  Implement `localDateMs()` and `normalizeEvent()` by moving their current bodies
  from CalendarMath unchanged. Add `validateEvent(eventData, calendars, uid)`:

  ```js
  function validateEvent(eventData, calendars, uid) {
      if (!eventData || typeof eventData !== "object")
          return failure("event", errors.event)
      if (typeof uid !== "string" || uid.length === 0)
          return failure("uid", "Event identifier is required")

      const calendar = calendars.find(item => item.id === eventData.calendarId)
      if (!calendar)
          return failure("calendarId", errors.calendarId)
      if (calendar.writable !== true)
          return failure("calendarId", "Calendar is read-only")

      const candidate = Object.assign({}, eventData, { uid })
      const normalized = normalizeEvent(candidate, calendars)
      if (normalized)
          return { ok: true, event: normalized }

      const allDay = candidate.allDay === true
      const startMs = allDay ? localDateMs(candidate.start)
          : typeof candidate.start === "string"
              && /(?:Z|[+-]\d{2}:\d{2})$/i.test(candidate.start)
              ? Date.parse(candidate.start) : NaN
      if (!Number.isFinite(startMs))
          return failure("start", errors.start)
      return failure("end", errors.end)
  }
  ```

  `createEvent()` rejects duplicate supplied UID with field `uid` and message
  `Event identifier already exists`; otherwise it validates, appends a canonical
  raw copy containing only `uid`, `calendarId`, `title`, `description`, `location`,
  `start`, `end`, `allDay`, and empty `reminders`, then returns
  `{ ok: true, event, rawEvents }`.
  `updateEvent()` finds and normalizes existing event, rejects missing/read-only,
  validates merged editable fields, preserves UID/reminders/readOnly/color, maps
  one raw item, and returns same success shape. `deleteEvent()` performs same
  target/permission checks, filters one item, and returns
  `{ ok: true, uid, rawEvents }`. Export all four functions for Node.

- [x] **Step 4: Run GREEN mutation tests**

  Run: `TZ=Europe/Paris node tests/test-event-mutation.js`

  Expected: `EventMutation tests passed`.

- [x] **Step 5: Finish normalizer extraction**

  Remove `localDateMs()`, `normalizeEvent()`, and its CommonJS export from
  `common/CalendarMath.js`. Remove migrated normalize blocks from
  `tests/test-calendar-math.js`. In CalendarService add:

  ```qml
  import "../common/EventMutation.js" as EventMutation
  ```

  Replace its normalization call with:

  ```qml
  const result = EventMutation.normalizeEvent(event, root.sourceCalendars)
  ```

- [x] **Step 6: Add replaceable state and service methods**

  Change `readonly property var rawEvents` to `property var rawEvents`. Add
  `property int nextMockUid: 1` and these service methods:

  ```qml
  function availableUid() {
      let uid = "mock-" + root.nextMockUid;
      while (root.rawEvents.some(event => event.uid === uid)) {
          ++root.nextMockUid;
          uid = "mock-" + root.nextMockUid;
      }
      return uid;
  }

  function createEvent(eventData) {
      const result = EventMutation.createEvent(root.rawEvents,
          root.sourceCalendars, eventData, root.availableUid());
      if (!result.ok)
          return result;
      root.rawEvents = result.rawEvents;
      ++root.nextMockUid;
      return { ok: true, event: result.event };
  }

  function updateEvent(uid, eventData) {
      const result = EventMutation.updateEvent(
          root.rawEvents, root.sourceCalendars, uid, eventData);
      if (!result.ok)
          return result;
      root.rawEvents = result.rawEvents;
      return { ok: true, event: result.event };
  }

  function deleteEvent(uid) {
      const result = EventMutation.deleteEvent(
          root.rawEvents, root.sourceCalendars, uid);
      if (!result.ok)
          return result;
      root.rawEvents = result.rawEvents;
      return { ok: true, uid: result.uid };
  }
  ```

- [x] **Step 7: Verify Checkpoint 1**

  Run:

  ```bash
  TZ=Europe/Paris node tests/test-event-mutation.js
  TZ=Europe/Paris node tests/test-calendar-math.js
  node tests/test-zoom.js
  qmllint services/CalendarService.qml
  ```

  Expected: three success messages and no QML diagnostics. No manual runtime UI
  exists yet; continue directly to Checkpoint 2 after reporting this boundary.

#### Checkpoint 2: Shared Editor And Header Create

**Files:**
- Create: `ui/EventEditorPanel.qml`
- Modify: `ui/CalendarWindow.qml`

**Interfaces:**
- EventEditorPanel requires `calendarService`, `mode`, `eventData`, `defaults`.
- Signals: `saved(var eventData)` and `cancelRequested()`.
- `mode` is exactly `"create"` or `"edit"`.
- Defaults are `{ allDay, startMs, endMs }` local timestamps.

- [x] **Step 1: Create editor state and conversion helpers**

  Build `ui/EventEditorPanel.qml` as a right-side Rectangle importing
  `QtQuick`, `QtQuick.Layouts`, and `QtQuick.Controls as Controls`. Add draft
  properties `titleText`, `calendarId`, `allDay`, `startDateText`, `endDateText`,
  `startTimeText`, `endTimeText`, `locationText`, `descriptionText`, `errorField`,
  and `errorMessage`. Filter writable calendars from
  `calendarService.calendars`.

  Implement exact local conversion helpers:

  ```qml
  function dateText(date) {
      return date.getFullYear() + "-"
          + String(date.getMonth() + 1).padStart(2, "0") + "-"
          + String(date.getDate()).padStart(2, "0");
  }

  function timeText(date) {
      return String(date.getHours()).padStart(2, "0") + ":"
          + String(date.getMinutes()).padStart(2, "0");
  }

  function parseDate(text) {
      const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
      if (!match)
          return null;
      const date = new Date(Number(match[1]), Number(match[2]) - 1,
          Number(match[3]));
      return date.getFullYear() === Number(match[1])
              && date.getMonth() === Number(match[2]) - 1
              && date.getDate() === Number(match[3]) ? date : null;
  }

  function parseDateTime(dateValue, timeValue) {
      const date = root.parseDate(dateValue);
      const match = /^(\d{2}):(\d{2})$/.exec(timeValue);
      if (!date || !match || Number(match[1]) > 23 || Number(match[2]) > 59)
          return null;
      date.setHours(Number(match[1]), Number(match[2]), 0, 0);
      return date;
  }
  ```

  On completion, initialize from normalized `eventData` in edit mode; subtract
  one local day from all-day exclusive end for UI. Otherwise initialize from
  `defaults`. Choose first writable calendar when no calendar ID is supplied.

- [x] **Step 2: Render locally styled controls**

  Use one internal `component FieldLabel: Text` and one vertical Flickable/Column.
  Render title TextField, writable-calendar ComboBox, CheckBox, start/end date
  TextFields, time TextFields visible only when not all-day, location TextField,
  description TextArea, one error Text, Cancel button, and Save button. Bind field
  border color to `errorField`; use Theme background/surface/text values. Do not
  add a separate QML file for one-off field chrome.

- [x] **Step 3: Serialize and save without losing input**

  Add `setError(field, message, control)` and `save()`:

  ```qml
  function save() {
      root.errorField = "";
      root.errorMessage = "";
      const startDate = root.parseDate(root.startDateText);
      if (!startDate)
          return root.setError("start", "Enter start date as YYYY-MM-DD", startDateField);
      const endDate = root.parseDate(root.endDateText);
      if (!endDate)
          return root.setError("end", "Enter end date as YYYY-MM-DD", endDateField);

      let start;
      let end;
      if (root.allDay) {
          endDate.setDate(endDate.getDate() + 1);
          start = root.dateText(startDate);
          end = root.dateText(endDate);
      } else {
          const startValue = root.parseDateTime(
              root.startDateText, root.startTimeText);
          const endValue = root.parseDateTime(
              root.endDateText, root.endTimeText);
          if (!startValue)
              return root.setError("start", "Enter start time as HH:mm", startTimeField);
          if (!endValue)
              return root.setError("end", "Enter end time as HH:mm", endTimeField);
          start = startValue.toISOString();
          end = endValue.toISOString();
      }

      const data = {
          calendarId: root.calendarId,
          title: root.titleText,
          description: root.descriptionText,
          location: root.locationText,
          allDay: root.allDay,
          start,
          end
      };
      const result = root.mode === "edit"
          ? root.calendarService.updateEvent(root.eventData.uid, data)
          : root.calendarService.createEvent(data);
      if (!result.ok)
          return root.setError(result.field, result.message, null);
      root.saved(result.event);
  }
  ```

  `setError` changes no draft property and calls `forceActiveFocus()` when a
  matching control is supplied.

- [x] **Step 4: Add CalendarWindow editor routing**

  Add `property var editorRequest: null`. Add:

  ```qml
  function headerCreateDefaults() {
      const start = new Date(root.selectedDate.getFullYear(),
          root.selectedDate.getMonth(), root.selectedDate.getDate(), 9);
      return { allDay: false, startMs: start.getTime(),
          endMs: start.getTime() + 60 * 60 * 1000 };
  }

  function openCreate(defaults) {
      root.editorRequest = { mode: "create", eventData: null,
          defaults: defaults };
      root.selectedEvent = null;
  }

  function cancelEditor() {
      if (root.editorRequest && root.editorRequest.mode === "edit") {
          root.editorRequest = null;
          return;
      }
      root.closeEventDetails();
  }

  function editorSaved(eventData) {
      root.selectedEvent = eventData;
      root.editorRequest = null;
  }
  ```

  Change overlay Loader activation to
  `root.selectedEvent !== null || root.editorRequest !== null`. Inside existing
  modal overlay, replace direct EventDetailsPanel with a panel Loader choosing
  editor or details Component. Editor cancel closes overlay in create mode; save
  calls `editorSaved` without destroying modal between panels. Extend
  `closeEventDetails()` and its existing zero-delay timer to clear both
  `selectedEvent` and `editorRequest`; this keeps create-cancel, scrim dismissal,
  navigation, and view switches deferred and click-through safe without another
  timer.

- [x] **Step 5: Add header New button**

  Add NavButton beside Today:

  ```qml
  NavButton {
      label: "New"
      buttonWidth: 42
      enabled: root.calendarService.calendars.some(
          calendar => calendar.writable === true)
      opacity: enabled ? 1 : 0.45
      onClicked: root.openCreate(root.headerCreateDefaults())
  }
  ```

  Inherited Item `enabled` disables its TapHandler; no custom guard is needed.

- [x] **Step 6: Verify and manually test Checkpoint 2**

  Run all three Node suites plus:

  ```bash
  qmllint ui/EventEditorPanel.qml ui/CalendarWindow.qml services/CalendarService.qml
  ```

  Manual test: New opens 09:00-10:00 selected-date draft; cancel changes nothing;
  invalid date/time preserves every field and marks one field; valid save appears
  in Week/Month/Agenda and opens details; restart restores fixtures.

#### Checkpoint 3: Edit And Confirmed Delete

**Files:**
- Modify: `ui/EventDetailsPanel.qml`
- Modify: `ui/CalendarWindow.qml`

**Interfaces:**
- EventDetailsPanel adds `editRequested(var eventData)` and
  `deleted(string uid)`.
- Read-only events expose neither action.
- Editor cancel in edit mode returns to unchanged details.

- [x] **Step 1: Add writable action state and buttons**

  In EventDetailsPanel add `property bool confirmingDelete: false`,
  `property string actionError: ""`, and both signals. After status content,
  render Edit and Delete buttons only when `eventData && !eventData.readOnly`.
  Edit emits `editRequested(eventData)`. First Delete sets
  `confirmingDelete = true`.

- [x] **Step 2: Add inline delete confirmation**

  While confirming, replace actions with text `Delete this event permanently?`
  and Cancel/Delete permanently buttons. Cancel resets confirmation only. Confirm
  calls service directly:

  ```qml
  const result = root.calendarService.deleteEvent(root.eventData.uid);
  if (result.ok)
      root.deleted(result.uid);
  else
      root.actionError = result.message;
  ```

  Keep drawer open on failure and render `actionError`; never expose actions for
  read-only University events.

- [x] **Step 3: Route edit/delete in CalendarWindow**

  Add:

  ```qml
  function openEdit(eventData) {
      if (!eventData || eventData.readOnly)
          return;
      root.editorRequest = { mode: "edit", eventData,
          defaults: null };
  }

  function eventDeleted() {
      root.clearViewSelection();
      root.closeEventDetails();
  }
  ```

  Wire details signals. Editor cancel in edit mode only clears `editorRequest`,
  revealing still-retained `selectedEvent`; create cancel clears whole overlay.
  Successful edit replaces `selectedEvent` with returned normalized event.

- [x] **Step 4: Verify and manually test Checkpoint 3**

  Run all Node suites and QML lint on EventEditorPanel, EventDetailsPanel,
  CalendarWindow, and CalendarService. Manual test: University details show no
  actions; Personal edit cancel preserves state; invalid edit preserves input;
  valid edit updates every view and opens updated details; delete cancel preserves
  event; confirmed delete removes it everywhere and closes without click-through.

#### Checkpoint 4: Contextual Blank Double-Click Creation

**Files:**
- Modify: `ui/WeekView.qml`
- Modify: `ui/MonthView.qml`
- Modify: `ui/AgendaView.qml`
- Modify: `ui/CalendarWindow.qml`

**Interfaces:**
- Every view adds `signal createRequested(var defaults)`.
- Defaults always contain `{ allDay, startMs, endMs }`.
- Existing card double-click remains Event Details and never emits create.

- [x] **Step 1: Add Week contextual defaults**

  Add the signal. In all-day background MouseArea, add `onDoubleClicked` deriving
  day index from `(mouse.x - root.gutterWidth) / root.dayWidth`; for valid indexes
  emit local midnight through next midnight with `allDay: true`.

  In timed grid background MouseArea, add:

  ```qml
  onDoubleClicked: mouse => {
      const dayIndex = Math.floor((mouse.x - root.gutterWidth) / root.dayWidth);
      if (dayIndex < 0 || dayIndex > 6)
          return;
      const minutes = Math.max(0, Math.min(1380,
          Math.floor(mouse.y / root.hourHeight) * 60));
      const date = CalendarMath.addDays(root.weekStart, dayIndex);
      const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(),
          Math.floor(minutes / 60), minutes % 60);
      root.createRequested({ allDay: false, startMs: start.getTime(),
          endMs: start.getTime() + 60 * 60 * 1000 });
  }
  ```

- [x] **Step 2: Add Month and Agenda contextual defaults**

  Add signal to both views. In Month day background and Agenda day-row MouseAreas:

  ```qml
  onDoubleClicked: {
      const start = CalendarMath.dayStart(modelData.date);
      const end = CalendarMath.addDays(start, 1);
      root.createRequested({ allDay: true, startMs: start.getTime(),
          endMs: end.getTime() });
  }
  ```

  Use each delegate ID (`dayColumn.modelData.date` or `dayRow.modelData.date`) so
  scope is explicit. Keep existing `onClicked: root.clearSelection()`.

- [x] **Step 3: Wire view signals to editor**

  In all three CalendarWindow view Components add:

  ```qml
  onCreateRequested: defaults => root.openCreate(defaults)
  ```

- [x] **Step 4: Run complete static gate**

  Run:

  ```bash
  TZ=Europe/Paris node tests/test-event-mutation.js
  TZ=Europe/Paris node tests/test-calendar-math.js
  node tests/test-zoom.js
  qmllint services/CalendarService.qml ui/EventEditorPanel.qml ui/EventDetailsPanel.qml ui/EventCard.qml ui/WeekView.qml ui/MonthView.qml ui/AgendaView.qml ui/CalendarWindow.qml
  ```

  Expected: three success messages and no QML diagnostics.

- [x] **Step 5: Verify final runtime acceptance**

  Manually test each blank double-click default, ensure event-card double-click
  still opens details, validate all-day inclusive end and timed whole-hour defaults,
  then repeat create/edit/delete/view switching/visibility toggles. Inspect runtime
  output for warnings and restart to confirm session-only reset.

## Stage 5: Reminder Interface

**Ownership:** QML displays and edits reminder metadata only. CalendarService
remains the frontend boundary. Future native helper owns scheduling and delivery;
transport stays unspecified. No scheduler, Timer, polling, daemon, subprocess,
`notify-send`, ICS write, pimsync integration, or helper transport is added.

**Contract:** Reminders use `{ minutesBefore }`, where the value is a nonnegative
safe integer. Source normalization filters malformed and duplicate optional
entries without rejecting an otherwise valid event. Create/update validation
strictly rejects malformed or duplicate arrays with field `reminders`. Updates
replace explicitly supplied reminders and preserve normalized existing reminders
when omitted. All service boundaries copy arrays and entries.

**Editor:** Create begins with no reminders; edit clones current reminders. Users
may add multiple preset or custom whole-minute offsets and remove entries.
Duplicate and invalid custom values remain in draft context and show one inline
error. Save sends a copied reminder array through existing mutation methods;
Cancel changes no service state.

- [x] Add failing EventMutation tests for normalization, strict validation,
  create/update semantics, omitted updates, and defensive copies.
- [x] Implement canonical reminder normalization and mutation validation.
- [x] Add and test shared reminder labels for minute/hour/day presets.
- [x] Add editor draft state, preset/custom controls, remove controls, inline
  validation, load behavior, and save payload.
- [x] Run Node suites, targeted QML lint, and focused code review.
- [ ] Manually verify reminder editor behavior and session-only reset.

## Stage 6: Personal Calendar Persistence

**Storage:** Personal events use the versioned document
`~/.local/share/calendar/personal.json`. Missing storage starts empty; existing
Personal mock fixtures are not migrated. Imported source events remain separate
and read-only.

**Safety:** The calendar is the sole writer. Every successful create, edit, or
delete performs an immediate atomic write before publishing new in-memory state.
Malformed JSON, unsupported or unknown schema fields, invalid events, duplicate
or source-colliding UIDs, unavailable storage, and write failures leave existing
disk and published state unchanged.

**Boundary:** `CalendarService` remains the only UI-facing event API. This stage
adds no watcher, backup recovery, helper, ICS handling, pimsync integration,
recurrence, or reminder scheduling. A future exporter may map stable Personal
UIDs to one ICS file per event; bidirectional reconciliation requires a separate
design.

- [x] Add strict version-1 Personal store parse/serialize tests.
- [x] Implement canonical Personal store validation and deterministic JSON.
- [x] Add `PersonalCalendarStore` with load-once and atomic blocking writes.
- [x] Route create/edit/delete through persistent storage and remove Personal
  mock fixtures.
- [x] Run JavaScript suites and targeted QML lint.
- [ ] Manually verify first-run initialization, restart persistence,
  create/edit/delete/reminders, malformed-file protection, and read-only source
  behavior.

## Stage 7: Calendar IPC Toggle

## Audit Follow-Up: Calendar Correctness

- [x] Disable header New while an editor draft is open.
- [x] Reject nonexistent local DST times instead of silently shifting them.
- [x] Validate explicit-offset ISO timestamps and Gregorian date components.
- [x] Parse all-day years below 100 without the Date constructor's 1900 offset.
- [x] Match Week all-day lane height to the 30px card stride.
- [x] Reset Agenda viewport on date navigation and explicit Today.
- [x] Make selecting the already-active Month view a no-op.
- [x] Run EventMutation, editor-date, CalendarMath, and Zoom Node checks;
  targeted QML lint passes without diagnostics.
- [ ] User runtime acceptance: editor/New, DST gap error, crowded all-day lane,
  Agenda Today/navigation, and repeated Month selection.

Parser/C++ files and external Hyprland close-handler integration are excluded.

## Stage 7 IPC Implementation Status

**Lifecycle:** Calendar Quickshell process remains running and starts with its
window hidden. Hiding preserves view, date, zoom, details, editor, and unsaved
draft state; existing visibility-bound timers stop while hidden.

**Contract:** `shell.qml` exposes `calendar.toggle(): bool` through
Quickshell IPC. Showing requests window activation. Hyprland owns persistent
startup with `qs -c calendar -d` and invokes
`qs -c calendar ipc call calendar toggle` from the user-defined binding.

- [x] Start `CalendarWindow` hidden.
- [x] Add typed `calendar.toggle(): bool` IPC handler.
- [x] Run static verification and focused review.
- [ ] Manually verify target registration, show/hide, focus, and preserved state.

## Month Navigation Performance Fix

**Scope:** Approved frontend-only fix in `ui/MonthView.qml`,
`ui/CalendarWindow.qml`, and `tests/test-month-navigation.js`. No service,
parser/C++, persistence, dependency, or upstream donor change.

**Implementation:** Replace the eager full-year week Repeater/Flickable with a
ListView. Keep the bounded yearly JS week/event model, existing day/event content,
seven-column widths, month markers, selection, and crowded-row height formula.
Use no extra delegate cache (`cacheBuffer: 0`) and no delegate recycling; rows
read their own model data instead of indexing a potentially replaced year model.
An inline footer retains trailing viewport padding so the last week can align
at the top at every 2W-6W zoom level.

**Positioning:** Today and monthly arrows explicitly request positioning even
when selectedDate is unchanged. The component-owned zero-delay Timer coalesces
requests; `cancelFlick()` stops motion and `positionViewAtIndex(index,
ListView.Beginning)` jumps directly without animations or intermediate week
traversal. Flush pending layout before positioning, then flush newly created
variable-height rows and realign once. No cumulative week-offset scans remain.

**Restoration:** Guard visible-date feedback before publishing a replacement
ListView model or updating nominal row heights. Preserve the latest pending
target through zoom, resize, and data rebuilds. Native `indexAt()` tracks the
top-visible variable-height row; missing delegates leave the header unchanged.
A boundary week represents the month whose first day it contains. Today does
not overwrite an unchanged boundary-week header. Visible-date updates never
write selectedDate, avoiding navigation feedback loops.

**Tradeoffs:** Only QML row creation is virtualized; yearly JS grouping remains
unchanged. Zero cache minimizes retained delegates but may increase row creation
during scrolling. Node tests execute actual QML JS methods with mocked ListView
layout/positioning; they do not prove Qt rendering, event delivery, or latency.
Performance is not runtime measured; no claim of an instant response is verified.

- [x] Observe failing direct-index navigation regression before implementation.
- [x] Test 53/54-week and leap/DST years, all five zoom levels, crowded heights,
  first/last weeks, layout-shift realignment, unavailable delegates, model and
  geometry guard ordering, pending-target coalescing, year replacement, repeated
  same-date Today, and boundary-month header retention.
- [x] Preserve existing month-navigation assertions; focused review findings
  concerning Today header and model-reset ordering were fixed and re-reviewed.
- [x] Run all five commands with `TZ=Europe/Paris`: `node
  tests/test-event-mutation.js` -> `EventMutation tests passed`; `node
  tests/test-editor-dates.js` -> `Editor date tests passed (run with
  TZ=Europe/Paris)`; `node tests/test-calendar-math.js` -> `CalendarMath tests
  passed`; `node tests/test-month-navigation.js` -> `Month navigation tests
  passed`; `node tests/test-zoom.js` -> `Zoom tests passed`.
- [x] Run `qmllint -U ui/MonthView.qml ui/CalendarWindow.qml`: no output.
- [ ] User manual verification only; Quickshell was not launched. Check initial
  entry and repeated Today within/across years, Today during a flick, monthly
  arrows and boundary headers, first/last-week top alignment at 2W-6W, crowded
  weeks, Ctrl+wheel/right-click reset, resize and calendar visibility changes,
  selection/details/blank-day creation, horizontal alignment, and rapid view
  switching. Watch for delayed realignment, stale headers, null-delegate warnings,
  binding loops, and rendering stalls; measure responsiveness if needed.
