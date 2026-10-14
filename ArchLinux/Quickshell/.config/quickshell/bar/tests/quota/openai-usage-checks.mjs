import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const api = {};
const source = await readFile(new URL("../../services/OpenAiUsage.js", import.meta.url), "utf8").catch(() => "");
runInNewContext(source, api);
assert.equal(typeof api.parseStatus, "function");
const sample = { plan: "plus", allowed: true, limitReached: false, fetchedAt: 1900000000000,
    fiveHour: { usedPercent: 22, resetAt: 2000000000000 }, weekly: { usedPercent: 3, resetAt: null } };
assert.equal(api.parseStatus(JSON.stringify(sample)).fiveHour.usedPercent, 22);
assert.equal(api.remaining(sample.fiveHour), 78);
assert.equal(api.remaining({ usedPercent: 110 }), 0);
assert.equal(api.remaining(null), null);
for (const value of ["bad", "null", "[]", "{}", JSON.stringify({ ...sample, allowed: "yes" }),
    JSON.stringify({ ...sample, fiveHour: { usedPercent: -1, resetAt: 0 } }),
    JSON.stringify({ ...sample, fiveHour: null, weekly: null })])
    assert.equal(api.parseStatus(value), null);
assert.equal(api.countdown(null, 0), "unknown");
assert.equal(api.countdown(1000, 1000), "reset due");
assert.equal(api.countdown(3661000, 0), "1h 1m 1s");
assert.equal(api.countdown(90000000, 0), "1d 1h 0m");
assert.equal(typeof api.displayText, "function", "Quota chip formatter must exist");
assert.equal(api.displayText("weekly", sample, true), "󰨳 97%");
assert.equal(api.displayText("fiveHour", sample, true), "󰔛 78%");
assert.equal(api.displayText("both", sample, true), "󰨳 97% · 󰔛 78%", "Weekly precedes five-hour quota");
assert.equal(api.displayText("invalid", sample, true), "󰨳 97%");
assert.equal(api.displayText("both", sample, false), "󰨳 N/A · 󰔛 N/A", "Failed refresh must not display stale quota");
assert.equal(api.displayText("weekly", null, false), "󰨳 N/A");
assert.equal(api.displayText("both", { ...sample, weekly: null }, true), "󰨳 N/A · 󰔛 78%", "Missing window does not substitute another period");
assert.equal(api.displayText("both", { ...sample, fiveHour: null }, true), "󰨳 97% · 󰔛 N/A");
assert.equal(api.displayText("weekly", { ...sample, weekly: {usedPercent: 110} }, true), "󰨳 0%");
assert.equal(api.displayText("weekly", { ...sample, weekly: {usedPercent: 35.6} }, true), "󰨳 64%");
assert.equal(api.parseStatus(JSON.stringify(sample)).bankedResets, null);
for (const count of [0, 1, 3, 7])
    assert.equal(api.parseStatus(JSON.stringify({...sample, bankedResets: count})).bankedResets, count);
for (const count of [null, true, -1, 1.5, "2", {}, 9007199254740992]) {
    const parsed = api.parseStatus(JSON.stringify({...sample, bankedResets: count}));
    assert.equal(parsed.bankedResets, null);
    assert.equal(parsed.weekly.usedPercent, 3);
}
assert.equal(typeof api.bankedResetsText, "function");
assert.equal(api.bankedResetsText(1), "● ○ ○ ○ ○");
assert.equal(api.bankedResetsText(3), "● ● ● ○ ○");
assert.equal(api.bankedResetsText(0), "○ ○ ○ ○ ○");
assert.equal(api.bankedResetsText(7), "● ● ● ● ● +2");
for (const count of [null, undefined, -1, NaN, true, "2"])
    assert.equal(api.bankedResetsText(count), "Unavailable");
const widget = await readFile(new URL("../../widgets/OpenAiUsage.qml", import.meta.url), "utf8");
const rowsBody = widget.match(/function tooltipRows\(\) \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(rowsBody);
const tooltip = await readFile(new URL("../../widgets/SystemStatTooltip.qml", import.meta.url), "utf8");
assert.match(tooltip, /visible: statRow.showsDots\s+Layout.alignment: Qt.AlignVCenter/,
    "Circle row must align geometrically, not rely on glyph baselines");
assert.match(tooltip, /model: statRow.showsDots \? 5 : 0/);
assert.match(tooltip, /color: index < statRow.modelData.dotCount/);
assert.match(tooltip, /visible: !statRow.showsDots/, "Ordinary tooltip rows retain text values");
for (const available of [true, false]) {
    const root = {available, snapshot: {...sample, bankedResets: 1}, error: "Fetch failed", windowText: () => "window"};
    const rows = runInNewContext(`(function() {${rowsBody}})()`, {root, Usage: api, Qt: {formatDateTime: () => "time"}});
    assert.equal(rows.find(row => row.label === "Banked resets")?.value,
        available ? "● ○ ○ ○ ○" : "Unavailable", "Never show stale resets after fetch failure");
    assert.equal(rows.find(row => row.label === "Banked resets")?.dotCount, available ? 1 : null);
}
console.log("OpenAI quota display checks passed");
