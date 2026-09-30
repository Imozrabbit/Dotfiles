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
    modules: { network: true, wifiMenu: true, vpn: true, bluetooth: true, calendar: true, weather: true, cpu: true },
    workspaceDisplay: { minimumCount: 3, itemSpacing: 21, normalLabels: {}, specialLabels: {} }
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
    { name: "special:steam" }, { name: "special:rmpc" }, { name: "special:notes" }, { name: "1" }, { name: "special:notes" }
]);
assert.deepEqual(Array.from(specials, entry => entry.name), ["notes", "rmpc", "steam"]);
assert.equal(specials[0].label, "notes");
assert.equal(specials[1].label, "");

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

console.log("bar config checks passed");
