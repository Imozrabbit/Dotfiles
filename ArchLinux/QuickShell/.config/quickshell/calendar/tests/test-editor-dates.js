const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// Execute the actual QML JavaScript methods without constructing a GUI.
const source = fs.readFileSync(path.join(__dirname, "../ui/EventEditorPanel.qml"), "utf8")
const root = {}
const context = vm.createContext({ root, Date })
for (const name of ["parseDate", "parseDateTime"]) {
    const method = source.match(new RegExp("^    function " + name + "\\([^]*?^    }", "m"))
    assert.ok(method, name + " method missing")
    root[name] = vm.runInContext("(" + method[0] + ")", context)
}

assert.equal(root.parseDate("2026-02-30"), null)
assert.equal(root.parseDate("0099-09-02").getFullYear(), 99)
assert.equal(root.parseDateTime("2026-03-29", "02:30"), null)
assert.equal(root.parseDateTime("2026-03-29", "03:30").getHours(), 3)
assert.equal(root.parseDateTime("2026-03-28", "02:30").getHours(), 2)
console.log("Editor date tests passed (run with TZ=Europe/Paris)")
