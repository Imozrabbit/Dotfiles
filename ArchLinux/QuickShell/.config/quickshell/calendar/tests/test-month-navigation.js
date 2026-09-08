const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const CalendarMath = require("../common/CalendarMath.js")

function method(file, name, root, globals = {}) {
    const source = fs.readFileSync(path.join(__dirname, "../ui", file), "utf8")
    const match = source.match(new RegExp("^    function " + name + "\\([^]*?^    }", "m"))
    assert.ok(match, name)
    return vm.runInNewContext("(" + match[0] + ")", {
        root, CalendarMath, Date, viewLoader: { item: null }, ...globals
    })
}

for (const zoom of [2, 3, 6]) {
    const root = {
        currentView: "month", monthWeeksPerPage: zoom,
        monthVisibleDate: new Date(2026, 8, 21),
        clearViewSelection() {}, closeEventDetails() {}
    }
    const navigate = method("CalendarWindow.qml", "navigate", root)
    for (const [direction, year, month] of [[1, 2026, 9], [1, 2026, 10],
        [1, 2026, 11], [1, 2027, 0], [-1, 2026, 11], [-1, 2026, 10]]) {
        navigate(direction)
        assert.equal(root.selectedDate.getFullYear(), year)
        assert.equal(root.selectedDate.getMonth(), month)
        assert.equal(root.selectedDate.getDate(), 1)
    }
}

for (const target of [new Date(2026, 9, 1), new Date(2027, 0, 1), new Date(2024, 1, 1)]) {
    const start = CalendarMath.weekStart(target)
    const root = {
        weeks: [{ days: Array.from({ length: 7 }, (_, i) => ({ date: CalendarMath.addDays(start, i) })) }],
        visibleDate: new Date(2000, 0, 1), topVisibleWeekIndex() { return 0 }
    }
    method("MonthView.qml", "updateVisibleDate", root)()
    assert.equal(root.visibleDate.getTime(), target.getTime())
}

{
    const root = {
        bufferStart: CalendarMath.weekStart(new Date(2026, 8, 1)),
        bufferEnd: CalendarMath.addDays(CalendarMath.weekStart(new Date(2026, 8, 30)), 7),
        rangeEvents: [
            { uid: "multi", startMs: new Date(2026, 8, 2, 23).getTime(), endMs: new Date(2026, 8, 4, 1).getTime(), title: "multi" },
            { uid: "boundary", startMs: new Date(2026, 8, 5).getTime(), endMs: new Date(2026, 8, 6).getTime(), title: "boundary" }
        ]
    }
    const buckets = method("MonthView.qml", "buildEventBuckets", root)()
    const day = date => buckets.find(bucket => bucket.date.getTime() === CalendarMath.dayStart(date).getTime())
    assert.equal(Array.from(day(new Date(2026, 8, 2)).events, event => event.uid).join(), "multi")
    assert.equal(Array.from(day(new Date(2026, 8, 3)).events, event => event.uid).join(), "multi")
    assert.equal(Array.from(day(new Date(2026, 8, 4)).events, event => event.uid).join(), "multi")
    assert.equal(Array.from(day(new Date(2026, 8, 5)).events, event => event.uid).join(), "boundary")
    assert.strictEqual(day(new Date(2026, 8, 5)).events[0], root.rangeEvents[1])
    assert.equal(day(new Date(2026, 8, 6)).events.length, 0)
}
// Execute real QML methods against a ListView stand-in, not source assertions.
for (const year of [2012, 2024, 2026, 2027]) {
    for (const zoom of [2, 3, 4, 5, 6]) {
        const root = {
            bufferStart: CalendarMath.weekStart(new Date(year, 0, 1)),
            bufferEnd: CalendarMath.addDays(CalendarMath.weekStart(new Date(year, 11, 31)), 7),
            rangeEvents: [], nominalWeekHeight: 600 / zoom,
            visibleDate: new Date(2000, 0, 1), positioning: true
        }
        root.bufferWeeks = CalendarMath.weekCount(root.bufferStart, root.bufferEnd)
        root.buildEventBuckets = method("MonthView.qml", "buildEventBuckets", root)
        root.weeks = method("MonthView.qml", "buildWeeks", root)()
        root.weeks[10].maxEvents = 40
        root.weekHeaderInset = method("MonthView.qml", "weekHeaderInset", root)
        root.weekHeight = method("MonthView.qml", "weekHeight", root)
        let layouts = 0
        let cancelled = 0
        let positioned = -1
        let origin = 1000
        const jumps = []
        const rowY = index => origin + root.weeks.slice(0, index).reduce((sum, _, i) => sum + root.weekHeight(i), 0)
        const list = {
            width: 700, height: 600, contentY: 0,
            cancelFlick() { ++cancelled },
            forceLayout() {
                ++layouts
                // Model/delegate layout can shift coordinates after a jump.
                if (positioned >= 0) { origin += 37; this.contentY += 19 }
            },
            positionViewAtIndex(index, mode) {
                assert.equal(mode, "Beginning")
                assert.ok(layouts > 0, "flush pending model layout before positioning")
                positioned = index
                jumps.push(index)
                this.contentY = rowY(index)
                root.updateVisibleDate()
            },
            indexAt(x, y) {
                assert.equal(x, this.width / 2)
                assert.equal(y, this.contentY)
                return root.weeks.findIndex((_, i) => y >= rowY(i) && y < rowY(i) + root.weekHeight(i))
            }
        }
        const globals = { pageFlickable: list, ListView: { Beginning: "Beginning" } }
        root.topVisibleWeekIndex = method("MonthView.qml", "topVisibleWeekIndex", root, globals)
        root.updateVisibleDate = method("MonthView.qml", "updateVisibleDate", root, globals)
        const positionDate = method("MonthView.qml", "positionDate", root, globals)
        for (const index of [0, 10, root.weeks.length - 1, 1]) {
            root.positioning = true
            const before = jumps.length
            positionDate(root.weeks[index].days[3].date)
            assert.ok(jumps.length > before)
            assert.ok(jumps.slice(before).every(target => target === index), "no intermediate week traversal")
            assert.equal(list.contentY, rowY(index), "align after delegate layout settles")
            assert.equal(root.positioning, false)
            const days = root.weeks[index].days
            assert.equal(root.visibleDate.getTime(), (days.find(day => day.date.getDate() === 1) || days[0]).date.getTime())
        }
        assert.ok(cancelled >= 4)
        assert.equal(root.weekHeight(10), 34 + root.weekHeaderInset(10) + 40 * 24)
        list.contentY = rowY(10) + root.weekHeight(10) - 0.01
        assert.equal(root.topVisibleWeekIndex(), 10, "crowded row stays top-visible to its actual end")
        list.contentY = rowY(11)
        assert.equal(root.topVisibleWeekIndex(), 11, "exact row boundary belongs to next week")
        const visible = root.visibleDate.getTime()
        root.positioning = true
        list.contentY = rowY(20)
        root.updateVisibleDate()
        assert.equal(root.visibleDate.getTime(), visible, "pending layout must not rewrite header/zoom anchor")
        root.positioning = false
        list.contentY = origin - 1
        root.updateVisibleDate()
        assert.equal(root.visibleDate.getTime(), visible, "no visible delegate during rebuild is safe")
        root.weeks = []
        positionDate(new Date(year, 0, 1))
        assert.equal(root.positioning, false)
    }
}

{
    const root = {
        visibleDate: new Date(2026, 9, 1), pendingPositionDate: new Date(2027, 0, 1),
        positioning: false, weeks: [{ days: [] }], weeksPerPage: 3
    }
    root.schedulePositionDate = date => { root.pendingPositionDate = date; root.positioning = true }
    const pageFlickable = { height: 600 }
    Object.defineProperty(pageFlickable, "model", {
        set(model) {
            assert.equal(root.positioning, true, "guard precedes model publication")
            assert.equal(model, root.weeks)
            assert.equal(root.pendingPositionDate, root.visibleDate)
        }
    })
    Object.defineProperty(root, "nominalWeekHeight", {
        set(height) {
            assert.equal(root.positioning, true, "guard precedes delegate geometry changes")
            assert.equal(height, 200)
        }
    })
    const globals = { pageFlickable }
    method("MonthView.qml", "rebuildModel", root, globals)()
    root.positioning = false
    method("MonthView.qml", "updateWeekHeight", root, globals)()
}

{
    // A year replacement is published during the pending ListView layout flush.
    const target = new Date(2027, 0, 1)
    const days = Array.from({ length: 7 }, (_, i) => ({ date: CalendarMath.addDays(CalendarMath.weekStart(target), i) }))
    const root = { weeks: [], positioning: true, visibleDate: new Date(2026, 8, 1) }
    let jumps = 0
    const pageFlickable = {
        width: 700, contentY: 0, cancelFlick() {},
        forceLayout() { root.weeks = [{ days }] },
        positionViewAtIndex(index, mode) { assert.equal(index, 0); assert.equal(mode, "Beginning"); ++jumps },
        indexAt() { return 0 }
    }
    const globals = { pageFlickable, ListView: { Beginning: "Beginning" } }
    root.topVisibleWeekIndex = method("MonthView.qml", "topVisibleWeekIndex", root, globals)
    root.updateVisibleDate = method("MonthView.qml", "updateVisibleDate", root, globals)
    method("MonthView.qml", "positionDate", root, globals)(target)
    assert.ok(jumps > 0)
    assert.equal(root.visibleDate.getTime(), target.getTime())
}

{
    const root = { visibleDate: new Date(2026, 9, 1), weeksPerPage: 3, positioning: false }
    let restarts = 0
    const globals = { positionTimer: { restart() { ++restarts } }, pageFlickable: { cancelFlick() {} } }
    root.schedulePositionDate = method("MonthView.qml", "schedulePositionDate", root, globals)
    // A geometry change may emit contentYChanged synchronously.
    Object.defineProperty(root, "weeksPerPage", {
        get() { return 3 },
        set(value) { assert.equal(value, 2); assert.equal(root.positioning, true) }
    })
    method("MonthView.qml", "setZoom", root)(2)
    assert.equal(root.pendingPositionDate.getTime(), root.visibleDate.getTime())
    const latest = new Date(2027, 0, 1)
    root.schedulePositionDate(latest)
    assert.equal(root.pendingPositionDate, latest)
    assert.equal(restarts, 2, "latest request replaces pending position")
    method("MonthView.qml", "setZoom", root)(2)
    assert.equal(root.pendingPositionDate, latest, "zoom must preserve a pending Today/year jump")
}

{
    const root = { updateWeekHeight() { ++root.heightUpdates }, heightUpdates: 0 }
    method("MonthView.qml", "handleWeeksPerPageChanged", root)()
    assert.equal(root.heightUpdates, 1, "MonthView must refresh row geometry after zoom changes")
}

for (const currentView of ["month", "week", "agenda"]) {
    const today = new Date(2026, 8, 6, 12)
    class FixedDate extends Date { constructor() { super(today.getTime()) } }
    const root = {
        currentView, selectedDate: today,
        clearViewSelection() {}, closeEventDetails() {}
    }
    let jumps = 0
    let resets = 0
    const item = {
        schedulePositionDate(date) { assert.equal(date.getTime(), today.getTime()); ++jumps },
        resetPosition() { ++resets }
    }
    const goToday = method("CalendarWindow.qml", "goToday", root, { Date: FixedDate, viewLoader: { item } })
    goToday()
    goToday()
    assert.equal(jumps, currentView === "month" ? 2 : 0, "same-date Today explicitly repositions Month")
    assert.equal(resets, currentView === "agenda" ? 2 : 0)
}

{
    const today = new Date(2026, 7, 31, 12)
    const representative = new Date(2026, 8, 1)
    class FixedDate extends Date { constructor() { super(today.getTime()) } }
    const root = {
        currentView: "month", selectedDate: today, monthVisibleDate: representative,
        clearViewSelection() {}, closeEventDetails() {}
    }
    // Same visible week emits no new visibleDateChanged signal.
    method("CalendarWindow.qml", "goToday", root, {
        Date: FixedDate, viewLoader: { item: { schedulePositionDate() {} } }
    })()
    assert.equal(root.monthVisibleDate, representative, "Today must not replace an unchanged boundary-week header")
}
console.log("Month navigation tests passed")
