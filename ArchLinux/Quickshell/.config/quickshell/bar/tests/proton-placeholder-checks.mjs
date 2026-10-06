import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
for (const name of ['Manager.qml','UpdatesTab.qml','InstalledTab.qml','LauncherTab.qml']) {
    const source = readFileSync(new URL('../proton/' + name, import.meta.url), 'utf8');
    for (const text of ['GE-Proton11-','20260928','1.3.0-1','Visual preview','Sample warning','Partial success: GE installed'])
        assert.ok(!source.includes(text), `${name}: remove placeholder ${text}`);
}
console.log('Proton placeholder checks passed');
