import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = name => readFileSync(new URL('../proton/' + name, import.meta.url), 'utf8');
const manager = read('Manager.qml'), updates = read('UpdatesTab.qml');
for (const text of ['id: tabCard','anchors.top: tabs.bottom','anchors.top: parent.top','anchors.leftMargin: 20','anchors.rightMargin: 20','Layout.minimumWidth: tabCard.width','Layout.maximumWidth: tabCard.width','model: ["Updates", "Installed", "Launcher"]']) assert.ok(manager.includes(text), text);
assert.ok(!manager.includes('parent: tabCard'));
for (const text of ['variant: "x86-64"','variant: "SLR · x86-64-v3"','textFormat: Text.RichText','text: "Newest installed"','horizontalAlignment: Text.AlignRight']) assert.ok(updates.includes(text), text);
assert.ok(!manager.includes('selectedTab === 3'));
console.log('Proton card checks passed');
