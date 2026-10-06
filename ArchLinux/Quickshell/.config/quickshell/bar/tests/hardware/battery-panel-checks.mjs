import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const source = await readFile(new URL("../../widgets/BatteryPanel.qml", import.meta.url), "utf8");
const root = {
    actionBusy: false,
    actionError: "",
    limitsNeedApply: true,
    limitSubmissionPending: false,
    pendingStartThreshold: 50,
    pendingEndThreshold: 55,
    chargeThresholdsRequested(start, end) {
        assert.equal(start, 50);
        assert.equal(end, 55);
        assert.equal(root.limitsNeedApply, false);
        root.actionBusy = true;
    }
};
const context = { root };
for (const name of ["submitLimits", "finishLimitSubmission"]) {
    const match = source.match(new RegExp(`function ${name}\\(\\) \\{([\\s\\S]*?)\\n    \\}`));
    assert.ok(match, `${name} must exist`);
    runInNewContext(`function ${name}() {${match[1]}\n}`, context);
}
root.finishLimitSubmission = context.finishLimitSubmission;

context.submitLimits();
context.finishLimitSubmission();
assert.equal(root.limitSubmissionPending, true, "keep submission pending while busy");
root.actionBusy = false;
context.finishLimitSubmission();
root.chargeStartThreshold = 0;
root.chargeEndThreshold = 100;
context.finishLimitSubmission();
assert.equal(root.limitsNeedApply, false, "readback fluctuation must not create an edit");

root.limitsNeedApply = true;
context.submitLimits();
root.actionError = "Could not change charge limits";
root.actionBusy = false;
context.finishLimitSubmission();
assert.equal(root.limitsNeedApply, true, "failed submission must remain retryable");
root.actionError = "";
context.finishLimitSubmission();
assert.equal(root.limitsNeedApply, true, "unrelated completion must not clear unsaved edits");

console.log("battery panel submission checks passed");
