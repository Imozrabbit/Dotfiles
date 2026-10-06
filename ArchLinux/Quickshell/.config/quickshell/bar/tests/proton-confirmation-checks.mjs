import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const manager = readFileSync(new URL('../proton/Manager.qml', import.meta.url), 'utf8');
const overlay = readFileSync(new URL('../proton/Confirmation.qml', import.meta.url), 'utf8');
for (const text of ['property var confirmation: null','root.service.prepareInstall(root.selectedFamily)','if (root.confirmation !== null)','id: confirmationOverlay','root.service.confirm(descriptor)']) assert.ok(manager.includes(text), text);
for (const text of ['"Confirm cleanup"','cleanupCandidates.map(item => item.name)','target.family === "ge"','root.confirmRequested()','root.cancelRequested()','z: 10']) assert.ok(overlay.includes(text), text);
assert.ok(manager.indexOf('id: confirmationOverlay') < manager.indexOf('// Shared footer'));
console.log('Proton confirmation checks passed');
