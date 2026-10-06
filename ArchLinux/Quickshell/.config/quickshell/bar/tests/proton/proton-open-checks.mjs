import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../../shell.qml', import.meta.url), 'utf8');
const open = source.match(/    function openProtonManager\(screen\) \{[\s\S]*?\n    \}/)?.[0];
assert.ok(open);
for (const [mode, enabled, expected] of [
    ['off', true, false], ['always', false, false],
    ['always', true, true], ['hover', true, true]
]) {
    const screen = {name:'fixture'};
    const root = {
        protonManagerWindow: {screen:null, visible:false},
        barConfig: {forScreen: () => ({mode, modules:{protonManager:enabled}})}
    };
    const api = {root};
    runInNewContext(open, api);
    api.openProtonManager(screen);
    assert.equal(root.protonManagerWindow.visible, expected, `${mode}, enabled=${enabled}`);
    assert.equal(root.protonManagerWindow.screen, expected ? screen : null);
    api.openProtonManager(null);
}
console.log('Proton opening respects off outputs and disabled modules');
