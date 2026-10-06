import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = name => readFileSync(new URL('../proton/' + name, import.meta.url), 'utf8');
const manager = read('Manager.qml');
const selector = read('GeSelector.qml');
const launcher = read('LauncherTab.qml');
const palette = read('Palette.qml');
assert.ok(!manager.includes('parent: tabCard'), 'No creation-time reparenting');
assert.ok(manager.includes('anchors.rightMargin: 3'), 'User-adjusted refresh position preserved');
assert.ok(manager.includes('Math.min(650'), 'Popup height remains capped');
assert.ok(selector.includes('height - 1'), 'Connected dropdown seam preserved');
assert.ok(selector.includes('bottomPadding: 6'), 'Dropdown bottom padding preserved');
assert.ok(selector.includes('property int rowHeight: 30'), 'Wheel spacing preserved');
assert.ok(!selector.includes('onCurrentIndexChanged:'), 'Wheel setup/navigation does not write umu');
assert.ok(launcher.includes('Layout.leftMargin: -3') && launcher.includes('Layout.rightMargin: -1'), 'User selector insets preserved');
for (const color of ['#E61C1C22','#151519','#1B1B20','#B6A1D8','#65C7D0']) assert.ok(palette.includes(color));
for (const name of ['Manager.qml','UpdatesTab.qml','InstalledTab.qml','LauncherTab.qml','GeSelector.qml','Confirmation.qml','Action.qml','Messages.qml'])
    assert.ok(!/#[0-9a-fA-F]{6,8}\b/.test(read(name)), `${name}: all colors named in palette`);
console.log('Proton UI structure/style checks passed');
