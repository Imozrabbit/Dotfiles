import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const parser = {};
const source = await readFile(new URL("../../services/MouseBatteryParser.js", import.meta.url), "utf8").catch(() => "");
runInNewContext(source, parser);
assert.equal(typeof parser.parseStatus, "function");
const valid = parser.parseStatus('{"battery":57,"charging":true,"connection":"wired"}');
assert.equal(valid.battery, 57);
assert.equal(valid.charging, true);
assert.equal(valid.connection, "wired");
assert.equal(parser.parseStatus('{"battery":0,"charging":false,"connection":"wireless"}').battery, 0);
for (const value of ["invalid", "null", "[]", "{}",
    '{"battery":101,"charging":true,"connection":"wired"}',
    '{"battery":"57","charging":true,"connection":"wired"}',
    '{"battery":57.5,"charging":true,"connection":"wired"}',
    '{"battery":57,"charging":"yes","connection":"wired"}',
    '{"battery":57,"charging":true,"connection":"unknown"}'])
    assert.equal(parser.parseStatus(value), null);

const service = await readFile(new URL("../../services/MouseBattery.qml", import.meta.url), "utf8");
function complete(order, exitCode = 0, text = '{"battery":57,"charging":true,"connection":"wired"}') {
    const root = { queryPending: true, available: false, outputFinished: false, errorFinished: false, exitCode: -1 };
    const context = { root, MouseBatteryParser: parser, queryOutput: { text }, queryError: { text: "WLMouse not found" }, watchdog: { stop() {} } };
    for (const name of ["clearStatus", "finishQuery"]) {
        const match = service.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n    \\}`));
        assert.ok(match);
        runInNewContext(match[0], context);
        root[name] = context[name];
    }
    for (const event of order) {
        if (event === "exit") root.exitCode = exitCode;
        else root[event] = true;
        context.finishQuery();
        if (!(root.outputFinished && root.errorFinished && root.exitCode >= 0))
            assert.equal(root.available, false, "must wait for exit and both streams");
    }
    return { root, finish: context.finishQuery };
}
for (const order of [["exit", "outputFinished", "errorFinished"], ["errorFinished", "outputFinished", "exit"], ["outputFinished", "exit", "errorFinished"]]) {
    const { root } = complete(order);
    assert.equal(root.available, true);
    assert.equal(root.percentage, 57);
    assert.equal(root.queryPending, false);
}
const failed = complete(["exit", "outputFinished", "errorFinished"], 1).root;
assert.equal(failed.available, false);
assert.equal(failed.percentage, -1);
assert.equal(failed.error, "WLMouse not found");
const invalid = complete(["exit", "outputFinished", "errorFinished"], 0, "invalid").root;
assert.equal(invalid.error, "Invalid mouse battery response");
const late = complete([]);
late.root.queryPending = false;
late.root.error = "Mouse query timed out";
late.root.exitCode = 0;
late.root.outputFinished = true;
late.root.errorFinished = true;
late.finish();
assert.equal(late.root.available, false, "late results must not replace timed-out state");
assert.equal(late.root.error, "Mouse query timed out");
console.log("mouse battery output checks passed");
