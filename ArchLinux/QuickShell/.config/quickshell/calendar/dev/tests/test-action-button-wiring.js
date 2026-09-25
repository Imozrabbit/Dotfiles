const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const ui = path.join(__dirname, "../../ui")
const sharedPath = path.join(ui, "ActionButton.qml")
assert.equal(fs.existsSync(sharedPath), true)
const shared = fs.readFileSync(sharedPath, "utf8")
assert.match(shared, /required property string label/)
assert.match(shared, /property bool primary: false/)
assert.match(shared, /property bool destructive: false/)
assert.match(shared, /property int minimumWidth: 80/)
assert.match(shared, /Qt\.lighter\(Theme\.accent, 1\.12\)/)
assert.match(shared, /cursorShape: root\.enabled \? Qt\.PointingHandCursor : Qt\.ArrowCursor/)

for (const name of ["EventDetailsPanel.qml", "EventEditorPanel.qml", "CalendarManagerPanel.qml"]) {
    const source = fs.readFileSync(path.join(ui, name), "utf8")
    assert.match(source, /ActionButton \{/)
    assert.doesNotMatch(source, /component ActionButton:/)
}

const manager = fs.readFileSync(path.join(ui, "CalendarManagerPanel.qml"), "utf8")
assert.equal((manager.match(/minimumWidth: 86/g) || []).length, 3)
console.log("Shared action button tests passed")
