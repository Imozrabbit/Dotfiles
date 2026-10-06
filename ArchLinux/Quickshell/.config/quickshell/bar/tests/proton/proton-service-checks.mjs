import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const directory = mkdtempSync('/tmp/opencode/proton-service-');
try {
    const fake = join(directory, 'helper.py');
    writeFileSync(fake, `import json,sys
request=json.loads(sys.argv[2])
if request['action']=='inspect': print('invalid output')
else: print(json.dumps({'id':request['id'],'type':'result','data':{'status':'error','area':'updates','messages':[{'severity':'error','text':'Fixture failure'}],'snapshot':None}}))
`);
    let service = readFileSync(new URL('../../proton/services/Service.qml', import.meta.url), 'utf8');
    service = service.replace('Quickshell.shellPath("proton/scripts/backend.py")', JSON.stringify(fake))
        .replace('"../core/State.js"', '"State.js"');
    writeFileSync(join(directory, 'Service.qml'), service);
    writeFileSync(join(directory, 'State.js'), readFileSync(new URL('../../proton/core/State.js', import.meta.url)));
    writeFileSync(join(directory, 'Check.qml'), `import QtQuick
import Quickshell
ShellRoot {
    Service {
        id: service
        config: ({compatibilityToolsDir:"/fixture",umuConfigPath:"/fixture/umu",sandboxCompatibilityToolsDir:"/sandbox"})
        property int stage: 0
        function lastAction() { return JSON.parse(command[3]).action; }
        Component.onCompleted: Qt.callLater(function() { stage = 1; open(); })
        onBusyChanged: {
            if (busy || stage === 0) return;
            if (stage === 1) {
                if (lastAction() !== "refresh" || lastAutomaticRefresh <= 0) { console.error("FAIL first open refresh"); Qt.exit(1); return; }
                stage = 2;
                Qt.callLater(function() { open(); });
            } else if (stage === 2) {
                if (lastAction() !== "inspect" || !messages.updates[0].text.includes("invalid")) { console.error("FAIL cached open"); Qt.exit(1); return; }
                lastAutomaticRefresh = Date.now() - 86400001;
                stage = 3;
                Qt.callLater(function() { open(); });
            } else if (stage === 3) {
                if (lastAction() !== "refresh" || messages.updates[0].text !== "Fixture failure") { console.error("FAIL expired daily refresh"); Qt.exit(1); return; }
                stage = 4;
                Qt.callLater(function() { refresh(); });
            } else {
                if (lastAction() !== "refresh" || messages.updates[0].text !== "Fixture failure") { console.error("FAIL manual refresh"); Qt.exit(1); return; }
                console.log("SERVICE PASS daily open cooldown and forced refresh"); Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL permanent busy"); Qt.exit(1); } }
}`);
    mkdirSync(join(directory, 'run'), { mode: 0o700 });
    const result = spawnSync('quickshell', ['-p', join(directory, 'Check.qml'), '--no-color'], {
        env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
            XDG_RUNTIME_DIR: join(directory, 'run'), XDG_CACHE_HOME: join(directory, 'cache'), XDG_STATE_HOME: join(directory, 'state'),
            QT_LOGGING_RULES: 'qml.debug=true;*.warning=true;*.critical=true', QT_FORCE_STDERR_LOGGING: '1' },
        encoding: 'utf8', timeout: 10000,
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, result.error?.message ?? output);
    assert.ok(output.includes('SERVICE PASS daily open cooldown and forced refresh'), output);
    console.log('Proton service daily refresh checks passed');
} finally { rmSync(directory, { recursive: true, force: true }); }
