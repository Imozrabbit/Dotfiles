import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../../proton/widgets/LauncherTab.qml', import.meta.url), 'utf8');
for (const text of ['id: launcherPackageCard','id: launcherProtonCard','id: locationsToggle','visible: locationsToggle.checked','root.packageState.messages.concat','root.service.snapshot?.messages.selection','text: "Sync latest GE"','root.service.syncGe()','root.service.selectGe(name)','id: geSelector','id: locationsContent','label:"Install directory"','label:"Sandbox directory"','label:"umu config"']) assert.ok(source.includes(text),text);
assert.ok(!source.includes('stateExamplesToggle'));
console.log('Proton Launcher checks passed');
