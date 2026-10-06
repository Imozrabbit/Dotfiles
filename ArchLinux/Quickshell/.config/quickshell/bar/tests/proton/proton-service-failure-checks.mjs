import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const directory = mkdtempSync('/tmp/opencode/proton-failure-');
try {
    const fake = join(directory, 'helper.py');
    writeFileSync(fake, `import json,sys,time
request=json.loads(sys.argv[2])
time.sleep(0.1)
messages={area:[] for area in ('updates','installed','package','selection')}
snapshot={'installations':[],'geVersions':[],'currentGeVersion':None,'releases':{},'package':{'state':'unavailable','installedVersion':None,'availableVersion':None,'messages':[]},'blockers':[],'locations':request['config'],'messages':messages}
print(json.dumps({'id':request['id'],'type':'result','data':{'status':'success','area':'updates','messages':[],'snapshot':snapshot}}))
`);
    mkdirSync(join(directory, 'run'), {mode:0o700});
    for (const scenario of ['startup', 'oversize', 'configIdle', 'configBusy', 'sameConfig', 'sameConfigBusy']) {
        let service = readFileSync(new URL('../../proton/services/Service.qml', import.meta.url), 'utf8')
            .replace('Quickshell.shellPath("proton/scripts/backend.py")', JSON.stringify(fake))
            .replace('"../core/State.js"', '"State.js"');
        if (scenario === 'startup') service = service.replace('"python3"', '"/missing-proton-python"');
        writeFileSync(join(directory, 'Service.qml'), service);
        writeFileSync(join(directory, 'State.js'), readFileSync(new URL('../../proton/core/State.js', import.meta.url)));
        writeFileSync(join(directory, 'Check.qml'), `import QtQuick
import Quickshell
ShellRoot {
    id: root
    property string scenario: "${scenario}"
    property var secondConfig: ({compatibilityToolsDir:"/second",umuConfigPath:"/second/umu",sandboxCompatibilityToolsDir:"/sandbox"})
    Service {
        id: service
        config: ({compatibilityToolsDir:"/first",umuConfigPath:"/first/umu",sandboxCompatibilityToolsDir:"/sandbox"})
        property bool changed: false
        Component.onCompleted: Qt.callLater(function() {
            if (root.scenario === "oversize") request("inspect", {padding:"x".repeat(200000)});
            else inspect();
            if (root.scenario === "configBusy") { changed = true; config = root.secondConfig; }
            if (root.scenario === "sameConfigBusy") config = Object.assign({}, config);
        })
        onBusyChanged: {
            if (!busy && root.scenario === "configIdle" && snapshot && !changed) {
                changed = true;
                config = root.secondConfig;
            }
            if (!busy && root.scenario === "sameConfig" && snapshot && !changed) {
                changed = true;
                lastAutomaticRefresh = 123456;
                config = Object.assign({}, config);
            }
        }
    }
    Timer {
        interval: 700; running: true
        onTriggered: {
            const failure = service.busy || (root.scenario.startsWith("sameConfig")
                ? !service.snapshot || service.snapshot.locations.compatibilityToolsDir !== "/first"
                    || root.scenario === "sameConfig" && service.lastAutomaticRefresh !== 123456
                : root.scenario.startsWith("config")
                ? !service.changed || service.snapshot !== null || service.confirmation !== null
                : service.messages.updates.length === 0);
            if (failure) { console.error("FAIL", root.scenario, "busy", service.busy, JSON.stringify(service.snapshot)); Qt.exit(1); }
            else { console.log("FAILURE CHECK PASS", root.scenario); Qt.quit(); }
        }
    }
}`);
        const result = spawnSync('quickshell', ['-p', join(directory, 'Check.qml'), '--no-color'], {
            encoding:'utf8', timeout:5000,
            env:{...process.env, QT_QPA_PLATFORM:'offscreen', QT_QUICK_BACKEND:'software', XDG_RUNTIME_DIR:join(directory,'run'), XDG_CACHE_HOME:directory, XDG_STATE_HOME:directory}
        });
        const output = result.stdout + result.stderr;
        assert.equal(result.status, 0, output);
        assert.ok(output.includes('FAILURE CHECK PASS'), output);
    }
    console.log('Proton startup/argument-limit/config-invalidation checks passed');
} finally { rmSync(directory, {recursive:true, force:true}); }
