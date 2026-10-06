import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const source = readFileSync(new URL('../../shell.qml', import.meta.url), 'utf8');
const loader = source.match(/id: protonManagerLoader[\s\S]*?(?=\n    LazyLoader)/)?.[0];
const binding = loader?.match(/barRevealed: ([^\n]+)/)?.[1];
assert.ok(binding, 'Proton manager must bind barRevealed to live per-output bar state');
assert.ok(!source.includes('root.protonManagerWindow.barRevealed ='), 'Opening must not overwrite live binding');
const directory = mkdtempSync('/tmp/opencode/proton-position-');
try {
    writeFileSync(join(directory, 'check.qml'), `import QtQuick
import Quickshell
ShellRoot {
    id: root
    property var protonManagerWindow: manager
    QtObject { id: firstScreen }
    QtObject { id: secondScreen }
    QtObject { id: firstBar; property var modelData: firstScreen; property bool barShown: true }
    QtObject { id: secondBar; property var modelData: secondScreen; property bool barShown: false }
    QtObject { id: outputBars; property var instances: [firstBar, secondBar] }
    QtObject { id: manager; property var screen: firstScreen; property bool barRevealed: ${binding} }
    function check(expected, message) {
        if (manager.barRevealed !== expected) throw new Error(message);
    }
    Component.onCompleted: Qt.callLater(function() {
        try {
            check(true, "initial revealed bar");
            firstBar.barShown = false;
            check(false, "hide while open");
            firstBar.barShown = true;
            check(true, "pin/reveal while open");
            manager.screen = secondScreen;
            check(false, "IPC opens on hidden second output");
            firstBar.barShown = false;
            check(false, "other output must not affect positioning");
            secondBar.barShown = true;
            check(true, "second output reveals");
            outputBars.instances = [firstBar];
            check(false, "removed output fallback");
            console.log("POSITION PASS"); Qt.quit();
        } catch (error) { console.error(error); Qt.exit(1); }
    })
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(1) }
}`);
    const result = spawnSync('quickshell', ['-p', join(directory, 'check.qml'), '--no-color'], {
        encoding: 'utf8', timeout: 10000,
        env: {...process.env, QT_QPA_PLATFORM:'offscreen', QT_QUICK_BACKEND:'software', XDG_CACHE_HOME:directory, XDG_STATE_HOME:directory}
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, output);
    assert.ok(output.includes('POSITION PASS'), output);
    console.log('Proton live per-output positioning checks passed');
} finally { rmSync(directory, {recursive:true, force:true}); }
