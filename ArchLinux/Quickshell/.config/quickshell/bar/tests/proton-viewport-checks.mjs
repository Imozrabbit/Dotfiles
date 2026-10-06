import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, readdirSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const directory = mkdtempSync('/tmp/opencode/proton-viewport-');
try {
    const module = new URL('../proton/', import.meta.url);
    for (const name of readdirSync(module).filter(name => name.endsWith('.qml') && name !== 'Service.qml'))
        writeFileSync(join(directory, name), readFileSync(new URL(name, module)));
    writeFileSync(join(directory, 'State.js'), readFileSync(new URL('State.js', module)));
    let source = readFileSync(new URL('Manager.qml', module), 'utf8');
    source = source.replace(/^import Quickshell.*\n/gm, '').replace('PanelWindow {', 'Window {')
        .replace('required property var theme', 'property var theme: QtObject { property string fontFamily: "monospace"; property color workspaceEmptyColor: "#707072" }')
        .replace('required property var service', `property var service: QtObject {
            property var config: ({compatibilityToolsDir:"/fixture",umuConfigPath:"/fixture/umu",sandboxCompatibilityToolsDir:"/sandbox"})
            property bool busy: false
            property var progress: null
            property var confirmation: null
            property int writes: 0
            property var messages: ({updates:[],installed:[],package:[],selection:[]})
            property var snapshot: ({installations:[{name:"GE-Proton11-7",family:"ge",version:[11,7,0],path:"/fixture/GE-Proton11-7",umuSelected:true}],geVersions:["GE-Proton11-7"],currentGeVersion:"GE-Proton11-7",releases:{},package:{state:"notInstalled",installedVersion:null,availableVersion:"1.3",messages:[]},blockers:[],messages:{updates:Array.from({length:25},(_,i)=>({severity:"warning",text:"Long operation result " + i})),installed:[],package:[],selection:[]}})
            function open() {}
            function refresh() {}
            function selectGe(name) { writes++; }
            function syncGe() { writes++; }
            function prepareInstall(family) {}
            function prepareRemove(name) {}
            function confirm(descriptor) {}
        }`)
        .replace('focusable: true', 'width: 1080; height: 1080')
        .replace('    anchors { top: true; bottom: true; left: true; right: true }\n', '')
        .replace(/^    WlrLayershell\..*\n/gm, '');
    source = source.replace('    Shortcut {', `
    property int testStage: 0
    function checkViewport() {
        if (tabs.parent !== tabCard || scroll.parent !== tabCard || !scroll.clip
            || scroll.y < tabs.y + tabs.height || scroll.y + scroll.height > updateActions.y
            || scroll.height <= 0 || scroll.contentHeight <= scroll.height
            || tabContents.parent !== scroll.contentItem.contentItem) {
            console.error("FAIL viewport", scroll.y,scroll.height,scroll.contentHeight,updateActions.y);
            Qt.exit(1); return false;
        }
        return true;
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            root.testStage++;
            if (root.testStage === 1 || root.testStage === 7) root.visible = true;
            else if (root.testStage === 2) { if (!root.checkViewport()) return; root.selectedTab = 1; }
            else if (root.testStage === 3) installedTab.toggleVersion("GE-Proton11-7");
            else if (root.testStage === 4) root.selectedTab = 2;
            else if (root.testStage === 5) {
                if (launcherTab.menuOpen || root.service.writes !== 0) { console.error("FAIL implicit selection write"); Qt.exit(1); return; }
                root.service.snapshot = Object.assign({}, root.service.snapshot, {installations:[],geVersions:[],currentGeVersion:null});
            }
            else if (root.testStage === 6) { root.visible = false; root.selectedTab = 0; }
            else if (root.testStage === 8) {
                if (!root.checkViewport()) return;
                console.log("VIEWPORT PASS first-open, tabs, empty GE, reopen"); Qt.quit();
            }
        }
    }
    Shortcut {`);
    writeFileSync(join(directory, 'Manager.qml'), source);
    const result = spawnSync('qml6', [join(directory, 'Manager.qml')], {
        env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
            QT_LOGGING_RULES: 'qml.debug=true;*.warning=true;*.critical=true', QT_FORCE_STDERR_LOGGING: '1' },
        encoding: 'utf8', timeout: 10000,
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, result.error?.message ?? output);
    assert.ok(!/Cannot anchor|TypeError|ReferenceError|Cannot assign|Binding loop/.test(output), output);
    assert.ok(output.includes('VIEWPORT PASS'), output);
    console.log('Proton viewport checks passed (real split UI, first-open/tabs/empty GE/reopen)');
} finally { rmSync(directory, { recursive: true, force: true }); }
