import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const source = await readFile(new URL("../services/MemoryParser.js", import.meta.url), "utf8").catch(() => "");
const parser = {};
runInNewContext(source, parser);
assert.equal(typeof parser.parseMeminfo, "function", "memory parser must exist");

const sample = [
    "MemTotal:        1000 kB",
    "MemFree:          100 kB",
    "MemAvailable:     300 kB",
    "Buffers:           50 kB",
    "Cached:           200 kB",
    "SReclaimable:      40 kB",
    "Shmem:            20 kB",
    "SwapTotal:        500 kB",
    "SwapFree:         450 kB"
].join("\n");

const parsed = parser.parseMeminfo(sample);
assert.equal(parsed.memory.total, 1000);
assert.equal(parsed.memory.used, 700);
assert.equal(parsed.memory.available, 300);
assert.equal(parsed.swap.total, 500);
assert.equal(parsed.swap.used, 50);
assert.equal(parser.parseMeminfo(sample.replace("MemTotal:        1000 kB", "MemTotal:        broken kB")).memory, null);
assert.equal(parser.parseMeminfo(sample.replace("SwapFree:         450 kB", "")).swap, null);
assert.equal(parser.parseMeminfo(sample.replace("MemAvailable:     300 kB", "MemAvailable:    2000 kB")).memory, null);

if (process.env.CHECK_LIVE_MEMORY === "1") {
    const liveText = await readFile("/proc/meminfo", "utf8");
    const live = parser.parseMeminfo(liveText);
    const free = execFileSync("free", ["-k"], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" } }).split("\n");
    const mem = free.find(line => line.startsWith("Mem:")).trim().split(/\s+/);
    const swap = free.find(line => line.startsWith("Swap:")).trim().split(/\s+/);
    console.log(`Mem total/used/available: proc ${live.memory.total}/${live.memory.used}/${live.memory.available}, free ${mem[1]}/${mem[2]}/${mem[6]}`);
    console.log(`Swap total/used: proc ${live.swap.total}/${live.swap.used}, free ${swap[1]}/${swap[2]}`);
}

console.log("memory parser checks passed");
