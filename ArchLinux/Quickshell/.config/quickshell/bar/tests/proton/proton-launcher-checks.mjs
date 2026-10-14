import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../../proton/widgets/LauncherTab.qml', import.meta.url), 'utf8');
for (const text of ['id: launcherPackageCard','id: launcherProtonCard','id: locationsToggle','visible: locationsToggle.checked','root.packageState.messages.concat','root.service.snapshot?.messages.selection','text: "Sync latest GE"','root.service.syncGe()','root.service.selectGe(name)','id: geSelector','id: locationsContent']) assert.ok(source.includes(text),text);
for (const label of ['Install directory', 'Sandbox directory', 'umu config'])
    assert.match(source, new RegExp(`\\blabel\\s*:\\s*"${label}"`), label);
assert.ok(!source.includes('stateExamplesToggle'));
console.log('Proton Launcher checks passed');
