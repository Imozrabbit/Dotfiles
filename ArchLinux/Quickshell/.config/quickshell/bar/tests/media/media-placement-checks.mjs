import assert from 'node:assert/strict';
import { readFileSync, copyFileSync, mkdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { runInNewContext } from 'node:vm';

const read = file => readFileSync(new URL('../../' + file, import.meta.url), 'utf8');
const shell = read('shell.qml');
const uses = shell.match(/    function uses\(moduleName\) \{[\s\S]*?\n    \}/)?.[0];
const topPredicate = shell.match(/return (config[^\n]*config.modules.media);/)?.[1];
assert.ok(uses && topPredicate);
for (const mediaPosition of ['top', 'bottom']) {
    for (const mode of ['off', 'hover', 'always']) {
        for (const topMediaMode of ['off', 'hover', 'always']) {
            for (const enabled of [false, true]) {
                const config = {mediaPosition, mode, topMediaMode, modules:{media:enabled}};
                const root = {barConfig:{ready:true, forScreen:() => config}};
                const api = {root, Quickshell:{screens:[{name:'fixture'}]}, config};
                runInNewContext(uses, api);
                assert.equal(api.uses('media'), enabled && (mediaPosition === 'top' ? topMediaMode : mode) !== 'off', JSON.stringify(config));
                assert.equal(runInNewContext(topPredicate, api), enabled && mediaPosition === 'top' && topMediaMode !== 'off', JSON.stringify(config));
                root.barConfig.ready = false;
                assert.equal(api.uses('media'), false);
            }
        }
    }
}

const bar = read('BarWindow.qml');
const bottom = bar.match(/        Widgets\.Mpris \{[\s\S]*?\n        \}/)?.[0];
assert.ok(bottom, 'Bottom bar must compose the real MPRIS widget');
const geometry = bar.match(/        readonly property real leftEnd:[\s\S]*?readonly property real middleSpace:[^\n]+/)?.[0];
assert.ok(geometry);
assert.match(read('TopMediaWindow.qml'), /topPanel: true/);
const directory = mkdtempSync('/tmp/opencode/media-placement-');
try {
    for (const folder of ['core', 'widgets', 'run']) mkdirSync(join(directory, folder), {mode:0o700});
    for (const file of ['core/Theme.qml', 'widgets/Mpris.qml', 'widgets/SystemStatTooltip.qml'])
        copyFileSync(new URL('../../' + file, import.meta.url), join(directory, file));
    writeFileSync(join(directory, 'shell.qml'), `import QtQuick
import Quickshell
import "core" as Core
import "widgets" as Widgets
ShellRoot {
    id: root
    property var configuration: ({mediaPosition:"bottom"})
    property var modules: ({media:true})
    property int bottomMargin: -1
    property int toggles: 0
    property var mprisService: ({active:true,paused:false,canTogglePlaying:true,app:"fixture",title:"Long title ".repeat(100),artist:"Artist",togglePlaying:()=>root.toggles++})
    Core.Theme { id: theme }
    Item {
        id: barContents
        width: 1000; height: 35
${geometry}
        Item { id: workspaceBox; x:20; width:150 }
        Item { id: rightSection; x:800; width:180 }
${bottom.replace('theme: root.theme', 'theme: theme')}
    }
    property int stage: 0
    function check(condition, message) { if (!condition) { console.error("MEDIA FAIL", message); Qt.exit(1); } }
    Timer {
        interval: 80; running:true; repeat:true
        onTriggered: {
            if (root.stage === 0) {
                root.check(mediaBox.active && mediaBox.visible && mediaBox.scrolling && !mediaBox.topPanel, "bottom visible, scrolling, tooltip above");
                root.check(Math.abs(mediaBox.width - 630 * 0.7) < 0.1 && Math.abs(mediaBox.x - (170 + (630-mediaBox.width)/2)) < 0.1, "old center-gap geometry");
                mediaBox.togglePlayingRequested(); root.check(root.toggles === 1, "playback forwarding");
                root.configuration = {mediaPosition:"top"};
            } else if (root.stage === 1) {
                root.check(!mediaBox.active && !mediaBox.visible && !mediaBox.scrolling, "live switch hides bottom");
                root.configuration = {mediaPosition:"bottom"}; barContents.width = 200; rightSection.x = 100;
            } else if (root.stage === 2) {
                root.check(mediaBox.width === 0 && !mediaBox.visible, "overlapping sides hide media");
                workspaceBox.visible = false; rightSection.visible = false;
            } else if (root.stage === 3) {
                root.check(Math.abs(mediaBox.width-140) < 0.1 && Math.abs(mediaBox.x-30) < 0.1, "hidden side sections leave full gap");
                root.modules = {media:false};
            } else if (root.stage === 4) {
                root.check(!mediaBox.visible && !mediaBox.active, "disabled media");
                console.log("MEDIA PLACEMENT PASS"); Qt.quit();
            }
            root.stage++;
        }
    }
}`);
    const result = spawnSync('quickshell', ['-p', directory, '--no-color'], {
        encoding:'utf8', timeout:10000,
        env:{...process.env, QT_QPA_PLATFORM:'offscreen', QT_QUICK_BACKEND:'software', XDG_RUNTIME_DIR:join(directory,'run'), XDG_CACHE_HOME:directory, XDG_STATE_HOME:directory}
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, output);
    assert.ok(output.includes('MEDIA PLACEMENT PASS'), output);
    assert.ok(!/TypeError|ReferenceError|Binding loop|Cannot assign/.test(output), output);
} finally { rmSync(directory, {recursive:true, force:true}); }
console.log('MPRIS placement, service gating, center layout and live-switch checks passed');
