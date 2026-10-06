import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../widgets/Workspaces.qml', import.meta.url), 'utf8');
const expression = source.match(/color: (protonMouse\.containsMouse[^\n]+)/)[1];
const color = new Function('root', 'protonMouse', `return ${expression};`);
const theme = { launcherHoverColor: 'hover', launcherColor: 'active', workspaceEmptyColor: 'gray' };
for (const open of [false, true]) {
    for (const hovered of [false, true]) {
        assert.equal(color({ theme, protonManagerOpen: open }, { containsMouse: hovered }),
            hovered ? 'hover' : open ? 'active' : 'gray');
    }
}
const shell = readFileSync(new URL('../../shell.qml', import.meta.url), 'utf8');
const bar = readFileSync(new URL('../../BarWindow.qml', import.meta.url), 'utf8');
assert.match(shell, /readonly property var protonManagerScreen: root\.protonManagerWindow\?\.visible \? root\.protonManagerWindow\.screen : null/);
assert.match(bar, /protonManagerOpen: root\.shared\.protonManagerScreen === root\.modelData/);
assert.ok(shell.includes('function previewProton()') && shell.includes('function protonManager()'), 'IPC compatibility retained');
console.log('Proton icon checks passed');
