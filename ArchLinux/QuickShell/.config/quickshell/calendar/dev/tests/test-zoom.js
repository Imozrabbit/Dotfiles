const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const Zoom = require("../../common/Zoom.js")

const weekSource = fs.readFileSync(path.join(__dirname, "../../ui/WeekView.qml"), "utf8")
const windowSource = fs.readFileSync(path.join(__dirname, "../../ui/CalendarWindow.qml"), "utf8")
assert.match(windowSource, /property int weekZoomPercent: 70/)
assert.match(weekSource, /property int zoomPercent: 70/)
assert.match(weekSource, /root\.setZoom\(70\)/)

assert.equal(Zoom.nextPercent(100, 1), 110)
assert.equal(Zoom.nextPercent(110, -1), 100)
assert.equal(Zoom.nextPercent(50, -1), 50)
assert.equal(Zoom.nextPercent(150, 1), 150)

assert.equal(Zoom.hourHeight(100), 72)
assert.equal(Zoom.hourHeight(70), 50.4)
assert.equal(Zoom.hourHeight(110), 79.2)

assert.equal(Zoom.wheelDirection(false, 120), 0)
assert.equal(Zoom.wheelDirection(true, 120), 1)
assert.equal(Zoom.wheelDirection(true, -120), -1)
assert.equal(Zoom.wheelDirection(true, 0), 0)

assert.equal(Zoom.nextWeeksPerPage(3, 1), 2)
assert.equal(Zoom.nextWeeksPerPage(2, -1), 3)
assert.equal(Zoom.nextWeeksPerPage(2, 1), 2)
assert.equal(Zoom.nextWeeksPerPage(3, -1), 4)
assert.equal(Zoom.nextWeeksPerPage(4, -1), 5)
assert.equal(Zoom.nextWeeksPerPage(5, -1), 6)
assert.equal(Zoom.nextWeeksPerPage(6, -1), 6)

assert.equal(Zoom.anchoredOffset(400, 200, 50, 100, 2000), 900)
assert.equal(Zoom.anchoredOffset(1900, 200, 50, 100, 2000), 2000)

assert.equal(Zoom.trailingViewportPadding(600, 100), 500)
assert.equal(Zoom.trailingViewportPadding(600, 700), 0)

assert.equal(Zoom.separatorVisible(236, 708, 1), true)
assert.equal(Zoom.separatorVisible(0.5, 708, 1), false)
assert.equal(Zoom.separatorVisible(707.9999999999999, 708, 1), false)

{
    const source = fs.readFileSync(path.join(__dirname, "../../ui/AgendaView.qml"), "utf8")
    const match = source.match(/^    function setZoom\([^]*?^    }/m)
    assert.ok(match)
    const root = { zoomPercent: 100, zoomScale: 1 }
    const agendaFlickable = { contentY: 300 }
    Object.defineProperty(root, "zoomScale", { get() { return root.zoomPercent / 100 } })
    vm.runInNewContext("(" + match[0] + ")", { root, agendaFlickable })(150)
    assert.equal(root.zoomPercent, 150)
    assert.equal(agendaFlickable.contentY, 450)
}

console.log("Zoom tests passed")
