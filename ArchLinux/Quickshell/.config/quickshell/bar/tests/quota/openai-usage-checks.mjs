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
console.log("OpenAI quota display checks passed");
