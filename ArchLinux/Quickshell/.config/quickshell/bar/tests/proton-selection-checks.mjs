import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../proton/Manager.qml', import.meta.url), 'utf8');
for (const text of ['property string selectedFamily: ""','onFamilySelected: family => root.selectedFamily = family','text: "Clear selection"','onClicked: root.selectedFamily = ""','root.canManage && !!root.service.snapshot?.releases[root.selectedFamily]','anchors.bottom: updateActions.visible ? updateActions.top : parent.bottom']) assert.ok(source.includes(text),text);
assert.equal((source.match(/text: "Update & clean"/g) ?? []).length,1);
console.log('Proton selection checks passed');
