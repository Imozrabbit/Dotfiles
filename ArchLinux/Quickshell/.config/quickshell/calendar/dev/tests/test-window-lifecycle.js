const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "../../ui/CalendarWindow.qml"), "utf8")

assert.match(source, /border\.width: 0/)
assert.match(source, /bottomLeftRadius: 12/)
assert.match(source, /bottomRightRadius: 12/)
assert.match(source, /Math\.min\(1020, Math\.round\(\(root\.screen \? root\.screen\.width : 1020\) \* 0\.75\)\)/)
assert.doesNotMatch(source, /requestActivate\(/)
assert.match(source, /HyprlandFocusGrab/)
assert.match(source, /forceActiveFocus\(Qt\.MouseFocusReason\)/)
assert.match(source, /if \(!hovered \|\| focusGrab\.active\)/)
assert.match(source, /hideTimer\.restart\(\)/)
assert.match(source, /hideTimer\.stop\(\)/)

function method(name, root, globals = {}) {
    const match = source.match(new RegExp("^    function " + name + "\\([^]*?^    }", "m"))
    assert.ok(match, "CalendarWindow.qml is missing lifecycle function " + name)
    return vm.runInNewContext("(" + match[0] + ")", { root, ...globals })
}

function rootFor(focusedMonitor) {
    const currentScreen = { name: "current" }
    const screens = [currentScreen, { name: "focused" }, { name: "other" }]
    const Hyprland = { focusedMonitor }
    Hyprland.monitorFor = screen => ({ focused: Hyprland.focusedMonitor?.name === screen.name })
    const root = {
        screen: currentScreen,
        surfaceVisible: false,
        revealed: false,
        focusGrab: { active: true },
        hideTimer: {
            restartCalls: 0,
            stopCalls: 0,
            restart() { ++this.restartCalls },
            stop() { ++this.stopCalls }
        },
        activationCalls: 0,
        activate() { ++this.activationCalls },
        requestActivate() { ++this.activationCalls }
    }
    const globals = { Quickshell: { screens }, Hyprland, focusGrab: root.focusGrab, hideTimer: root.hideTimer }
    root.screenForFocusedMonitor = method("screenForFocusedMonitor", root, globals)
    root.showWindow = method("showWindow", root, globals)
    root.hideWindow = method("hideWindow", root, globals)
    root.toggleWindow = method("toggleWindow", root, globals)
    return { root, currentScreen, screens, Hyprland }
}

{
    const { root, currentScreen, screens, Hyprland } = rootFor({ name: "focused" })
    assert.strictEqual(root.screenForFocusedMonitor(), screens[1])
    Hyprland.focusedMonitor = null
    assert.strictEqual(root.screenForFocusedMonitor(), currentScreen)
    delete Hyprland.focusedMonitor
    assert.strictEqual(root.screenForFocusedMonitor(), currentScreen)
    Hyprland.focusedMonitor = { name: "missing" }
    assert.strictEqual(root.screenForFocusedMonitor(), currentScreen)
}

{
    const { root, screens } = rootFor({ name: "focused" })
    root.showWindow()
    assert.strictEqual(root.screen, screens[1])
    assert.equal(root.surfaceVisible, true)
    assert.equal(root.revealed, true)
    assert.equal(root.activationCalls, 0)
}

{
    const { root } = rootFor({ name: "focused" })
    root.surfaceVisible = true
    root.revealed = true
    root.hideWindow()
    assert.equal(root.revealed, false)
    assert.equal(root.surfaceVisible, true)
    assert.equal(root.focusGrab.active, false)
    assert.equal(root.hideTimer.restartCalls, 1)
}

{
    const { root } = rootFor({ name: "focused" })
    root.revealed = false
    assert.equal(root.toggleWindow(), true)
    assert.equal(root.revealed, true)
    assert.equal(root.activationCalls, 0)
    assert.equal(root.toggleWindow(), false)
    assert.equal(root.revealed, false)
    assert.equal(root.activationCalls, 0)
}
