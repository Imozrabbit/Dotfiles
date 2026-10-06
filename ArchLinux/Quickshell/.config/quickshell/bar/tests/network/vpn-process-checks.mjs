import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const source = await readFile(new URL("../../network/vpn/VpnDnsStatus.qml", import.meta.url), "utf8");
const processes = { vpnProcess: { requestDone: false }, deviceProcess: { requestDone: false }, dnsProcess: { requestDone: false } };
const root = { pending: 3, finish() { this.pending--; } };
for (const [id, process] of Object.entries(processes)) {
    const block = source.slice(source.indexOf(`id: ${id}`)).split("\n    Process {")[0];
    const handler = block.match(/onRunningChanged: \{([\s\S]*?)\n        \}/);
    assert.ok(handler, `${id} must complete failed starts`);
    const complete = source.match(/function complete\(([^)]*)\) \{([\s\S]*?)\n    \}/);
    assert.ok(complete, "completion must guard duplicate runningChanged/exited signals");
    const context = { root, ...processes };
    runInNewContext(`function complete(${complete[1]}) {${complete[2]}\n}`, context);
    root.complete = context.complete;
    runInNewContext(handler[1], context);
    const pending = root.pending;
    assert.equal(process.requestDone, true);
    root.complete(process, "ignored", []);
    assert.equal(root.pending, pending, "exit after error must not complete twice");
}
assert.equal(root.pending, 0, "failed starts must permit next poll");
console.log("VPN process failure checks passed");
