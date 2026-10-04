import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const source = await readFile(new URL("../core/BarConfig.js", import.meta.url), "utf8").catch(() => "");
const config = {};
runInNewContext(source, config);
assert.equal(typeof config.resolveConfig, "function", "config resolver must exist");
assert.equal(typeof config.screenConfig, "function", "screen resolver must exist");
assert.equal(typeof config.normalWorkspaceEntries, "function", "normal workspace discovery must exist");
assert.equal(typeof config.specialWorkspaceEntries, "function", "special workspace discovery must exist");

const defaults = {
    mode: "always",
    edgeSpacing: 14,
    hoverToggleEnabled: true,
    modules: { network: true, wifiMenu: true, vpn: true, bluetooth: true, calendar: true, weather: true, cpu: true, mouseBattery: false, openAiUsage: false },
    mouseBattery: { name: "WLMouse Beast X" },
    vpn: { routerManagedSsids: [] },
    workspaceDisplay: { minimumCount: 3, itemSpacing: 21, normalLabels: {}, specialLabels: {} },
    launchers: [{ icon: "D", tooltip: "Default", leftCommand: ["default-app"], rightCommand: [] }]
};

const missing = config.resolveConfig(defaults, "{}");
assert.equal(config.screenConfig(missing, "unknown").mode, "always");
assert.equal(config.screenConfig(missing, "unknown").modules.bluetooth, true);
assert.equal(config.screenConfig(missing, "unknown").edgeSpacing, 14);
assert.equal(config.resolveConfig(defaults, "broken json").modules.network, true);

const pc = config.resolveConfig(defaults, JSON.stringify({
    modules: { bluetooth: false, wifiMenu: false },
    monitors: {
        "DP-1": { mode: "hover", hoverToggleEnabled: false, modules: { cpu: false } },
        "DP-2": { mode: "off" }
    }
}));
assert.equal(config.screenConfig(pc, "DP-1").modules.network, true);
assert.equal(config.screenConfig(pc, "DP-1").modules.wifiMenu, false);
assert.equal(config.screenConfig(pc, "DP-1").modules.cpu, false);
assert.equal(config.screenConfig(pc, "DP-1").hoverToggleEnabled, false);
assert.equal(config.screenConfig(pc, "DP-2").mode, "off");
assert.equal(config.screenConfig(pc, "unlisted").modules.cpu, true);

const invalid = config.resolveConfig(defaults, JSON.stringify({
    mode: "sometimes", hoverToggleEnabled: "no", modules: { bluetooth: "false", unexpected: false },
    monitors: { "DP-1": { mode: 23, modules: { cpu: false } }, "../wrong": { mode: "off" } }
}));
assert.equal(config.screenConfig(invalid, "DP-1").mode, "always");
assert.equal(config.screenConfig(invalid, "DP-1").modules.cpu, false);
assert.equal(config.screenConfig(invalid, "unlisted").modules.bluetooth, true);
assert.equal(config.screenConfig(invalid, "../wrong").mode, "always");
assert.equal(Object.hasOwn(invalid.modules, "unexpected"), false);

const dependent = config.resolveConfig(defaults, JSON.stringify({ modules: { network: false, calendar: false } }));
assert.equal(config.screenConfig(dependent, "DP-1").modules.wifiMenu, false);
assert.equal(config.screenConfig(dependent, "DP-1").modules.vpn, false);
assert.equal(config.screenConfig(dependent, "DP-1").modules.weather, false);

const discovered = config.resolveConfig(defaults, "{}");
assert.equal(discovered.workspaceDisplay.itemSpacing, 21);
assert.equal(config.resolveConfig(defaults, '{"workspaceDisplay":{"itemSpacing":8}}').workspaceDisplay.itemSpacing, 8);
assert.equal(config.resolveConfig(defaults, '{"workspaceDisplay":{"itemSpacing":0}}').workspaceDisplay.itemSpacing, 0);
assert.equal(config.resolveConfig(defaults, '{"workspaceDisplay":{"itemSpacing":-1}}').workspaceDisplay.itemSpacing, 21);
assert.equal(config.resolveConfig(defaults, '{"workspaceDisplay":{"itemSpacing":"8"}}').workspaceDisplay.itemSpacing, 21);
assert.deepEqual(Array.from(config.normalWorkspaceEntries(discovered.workspaceDisplay, [{ id: 8 }, { id: 99 }, { id: 8 }, { id: -1 }]), entry => entry.id), [1, 2, 3, 8, 99]);
assert.equal(config.normalWorkspaceEntries(discovered.workspaceDisplay, [{ id: 8 }])[3].label, "8");
assert.deepEqual(Array.from(config.normalWorkspaceEntries(discovered.workspaceDisplay, []), entry => entry.id), [1, 2, 3]);

const personal = config.resolveConfig(defaults, JSON.stringify({ workspaceDisplay: {
    minimumCount: 7,
    normalLabels: { "4": "󰝆", "8": "Dev" },
    specialLabels: { rmpc: "" }
} }));
assert.deepEqual(Array.from(config.normalWorkspaceEntries(personal.workspaceDisplay, [{ id: 8 }]), entry => entry.id), [1, 2, 3, 4, 5, 6, 7, 8]);
assert.equal(config.normalWorkspaceEntries(personal.workspaceDisplay, [{ id: 8 }])[3].label, "󰝆");
assert.equal(config.normalWorkspaceEntries(personal.workspaceDisplay, [{ id: 8 }])[7].label, "Dev");
const specials = config.specialWorkspaceEntries(personal.workspaceDisplay, [
    { name: "special:steam", toplevels: { values: [{}] } },
    { name: "special:rmpc", toplevels: { values: [{}] } },
    { name: "special:notes", toplevels: { values: [{}] } },
    { name: "1" }, { name: "special:notes" }
]);
assert.deepEqual(Array.from(specials, entry => entry.name), ["notes", "rmpc", "steam"]);
assert.equal(specials[0].label, "notes");
assert.equal(specials[1].label, "");

const openMonitor = { lastIpcObject: { specialWorkspace: { name: "special:notes" } } };
const otherMonitor = { lastIpcObject: { specialWorkspace: { name: "" } } };
for (const occupied of [false, true]) {
    const workspaces = [{ name: "special:notes", toplevels: { values: occupied ? [{}] : [] } }];
    assert.equal(config.specialWorkspaceEntries(personal.workspaceDisplay, workspaces, [openMonitor], openMonitor)[0].state, "focused");
    assert.equal(config.specialWorkspaceEntries(personal.workspaceDisplay, workspaces, [openMonitor, otherMonitor], otherMonitor)[0].state, occupied ? "occupied" : "empty");
    const closed = config.specialWorkspaceEntries(personal.workspaceDisplay, workspaces, [otherMonitor], otherMonitor);
    if (occupied)
        assert.equal(closed[0].state, "occupied");
    else
        assert.equal(closed.length, 0, "closed empty workspace must not reserve a slot");
}
assert.equal(config.specialWorkspaceEntries(personal.workspaceDisplay, [], [openMonitor], openMonitor)[0].state, "focused", "open empty workspace must appear before workspace-list update");

const badWorkspaces = config.resolveConfig(defaults, JSON.stringify({ workspaceDisplay: {
    minimumCount: 1000000,
    normalLabels: { "0": "bad", "4": "", "5": "five" },
    specialLabels: { "": "bad", notes: "N" }
} }));
assert.equal(badWorkspaces.workspaceDisplay.minimumCount, 3);
assert.equal(config.normalWorkspaceEntries(badWorkspaces.workspaceDisplay, [{ id: 4 }])[3].label, "4");
assert.equal(config.normalWorkspaceEntries(badWorkspaces.workspaceDisplay, [{ id: 5 }])[3].label, "five");

const spacing = config.resolveConfig(defaults, JSON.stringify({
    edgeSpacing: 12,
    workspaceDisplay: { itemSpacing: 18, normalLabels: { "8": "Dev" } },
    monitors: {
        "DP-1": { edgeSpacing: 4, workspaceDisplay: { itemSpacing: 8 } },
        "DP-2": { edgeSpacing: -1, workspaceDisplay: { itemSpacing: "bad" } }
    }
}));
assert.equal(config.screenConfig(spacing, "DP-1").edgeSpacing, 4);
assert.equal(config.screenConfig(spacing, "DP-1").workspaceDisplay.itemSpacing, 8);
assert.equal(config.screenConfig(spacing, "DP-1").workspaceDisplay.normalLabels["8"], "Dev");
assert.equal(config.screenConfig(spacing, "DP-1").workspaceDisplay.minimumCount, 3);
assert.equal(config.screenConfig(spacing, "DP-2").edgeSpacing, 12);
assert.equal(config.screenConfig(spacing, "DP-2").workspaceDisplay.itemSpacing, 18);
assert.equal(config.screenConfig(spacing, "unlisted").workspaceDisplay.itemSpacing, 18);
assert.equal(config.resolveConfig(defaults, "partial json", spacing), spacing, "invalid live save preserves last valid settings");
assert.equal(config.resolveConfig(defaults, "[]", spacing), spacing);
assert.equal(config.screenConfig(config.resolveConfig(defaults, "{}", spacing), "DP-1").edgeSpacing, 14);

assert.equal(config.screenConfig(missing, "DP-1").launchers[0].icon, "D");
const customLaunchers = [{ icon: "F", tooltip: "Left click\nRight click", leftCommand: ["firefox", "a b"], rightCommand: [] }];
const apps = config.resolveConfig(defaults, JSON.stringify({ launchers: customLaunchers, monitors: { "DP-1": { launchers: [] } } }));
assert.equal(config.screenConfig(apps, "DP-1").launchers.length, 0);
assert.equal(config.screenConfig(apps, "DP-2").launchers.length, 1);
assert.equal(config.screenConfig(apps, "DP-2").launchers[0].tooltip, "Left click\nRight click");
assert.equal(config.screenConfig(apps, "DP-2").launchers[0].leftCommand[1], "a b");
const badApps = config.resolveConfig(defaults, JSON.stringify({ launchers: [
    { icon: "", leftCommand: ["bad"] },
    { icon: "X", leftCommand: "not an argument list" },
    { icon: "Y", rightCommand: [7] },
    { icon: "R", rightCommand: ["right-app"] }
] }));
assert.equal(badApps.launchers.length, 1);
assert.equal(badApps.launchers[0].icon, "R");
assert.equal(badApps.launchers[0].leftCommand.length, 0);
assert.equal(config.resolveConfig(defaults, '{"launchers":false}').launchers[0].icon, "D");
assert.equal(config.screenConfig(missing, "DP-1").modules.mouseBattery, false);
assert.equal(config.screenConfig(missing, "DP-1").mouseBattery.name, "WLMouse Beast X");
const namedMouse = config.resolveConfig(defaults, JSON.stringify({ mouseBattery: { name: "My mouse" }, monitors: { "DP-1": { modules: { mouseBattery: true } } } }));
assert.equal(config.screenConfig(namedMouse, "DP-1").mouseBattery.name, "My mouse");
assert.equal(config.screenConfig(namedMouse, "DP-1").modules.mouseBattery, true);
assert.equal(config.resolveConfig(defaults, '{"mouseBattery":{"name":""}}').mouseBattery.name, "WLMouse Beast X");
assert.equal(config.screenConfig(missing, "DP-1").modules.openAiUsage, false);
assert.equal(config.screenConfig(config.resolveConfig(defaults, '{"monitors":{"DP-1":{"modules":{"openAiUsage":true}}}}'), "DP-1").modules.openAiUsage, true);
assert.equal(config.resolveConfig(defaults, "{}").vpn.routerManagedSsids.length, 0);
assert.equal(config.resolveConfig(defaults, '{"vpn":{"routerManagedSsids":["Home",7,""]}}').vpn.routerManagedSsids.join(","), "Home");

console.log("bar config checks passed");
