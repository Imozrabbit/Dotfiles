import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';

const source=readFileSync(new URL('../shell.qml',import.meta.url),'utf8');
const root={microphoneName:'physical-mic',microphone:null,microphoneAudio:null,microphoneReady:false,microphoneMuted:false};
const Pipewire={nodes:{values:[{name:'virtual-source',isSink:false,isStream:false},{name:'physical-mic',isSink:false,isStream:false,audio:{muted:true},ready:true}]}};
function value(name) {
    const expression=source.match(new RegExp(`readonly property \\w+ ${name}: (.+)`));
    assert.ok(expression,`Missing ${name}`);
    return runInNewContext(expression[1],{root,Pipewire});
}
root.microphone=value('microphone');
assert.equal(root.microphone.name,'physical-mic','Track keybinding target, not virtual default');
root.microphoneAudio=value('microphoneAudio');
root.microphoneReady=value('microphoneReady');
root.microphoneMuted=value('microphoneMuted');
assert.equal(value('microphoneLabel'),'Muted');
const mutedIcon=value('microphoneIcon');
root.microphoneMuted=false;
assert.equal(value('microphoneLabel'),'Unmuted');
assert.notEqual(value('microphoneIcon'),mutedIcon);
root.microphoneReady=false;
assert.equal(value('microphoneLabel'),'Mic unavailable','Unbound/missing input cannot be reported unmuted');
Pipewire.nodes.values=[];
assert.equal(value('microphone'),null);
let reveals=0;
root.revealMicrophone=()=>reveals++;
const hook=source.match(/function microphone\(\): void \{([\s\S]*?)\n        \}/);
assert.ok(hook,'Missing unavailable-input IPC hook');
runInNewContext(hook[1],{root});
assert.equal(reveals,1);
root.microphoneReady=true;
runInNewContext(hook[1],{root});
assert.equal(reveals,1,'Available mic waits for actual PipeWire state, not potentially stale IPC state');

const directory=mkdtempSync('/tmp/opencode/mic-osd-');
try {
    mkdirSync(join(directory,'runtime'),{mode:0o700});
    // Native Qt runner cannot initialize Quickshell's engine. Stub only the icon
    // adapter; exercise the real component's colors, sizing and layout unchanged.
    const item=readFileSync(new URL('../OsdItem.qml',import.meta.url),'utf8')
        .replace(/^import Quickshell.*\n/gm,'').replace('Quickshell.iconPath(root.iconName)','""');
    writeFileSync(join(directory,'OsdItem.qml'),item);
    writeFileSync(join(directory,'IconImage.qml'),'import QtQuick\nItem { property int implicitSize:25; property string source:""; implicitWidth:implicitSize; implicitHeight:implicitSize }');
    writeFileSync(join(directory,'Check.qml'),`import QtQuick
Window {
    width:280; height:100; visible:true
    OsdItem { id: mic; width:280; height:40; statusOnly:true; iconName:"microphone-sensitivity-muted-symbolic"; label:"Mic unavailable"; fillLevel:0 }
    OsdItem { id: volume; y:50; width:280; height:40; iconName:"audio-volume-high-symbolic"; label:"100%"; fillLevel:1 }
    Timer { interval:100; running:true; onTriggered: {
        if (mic.color!==volume.color || mic.height!==volume.height) throw new Error("OSD theme mismatch");
        const row=mic.children[0];
        const label=row.children.find(child=>child.text==="Mic unavailable");
        const icon=row.children.find(child=>child.implicitSize===25);
        if (!label || !icon || label.width<label.implicitWidth || Math.abs((icon.x+label.x+label.width)/2-row.width/2)>1)
            throw new Error("Status text must fit and icon/text pair must be centered");
        console.log("MIC OSD PASS"); Qt.quit();
    }}
}`);
    const result=spawnSync('qml6',[join(directory,'Check.qml')],{encoding:'utf8',timeout:10000,
        env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software',QT_FORCE_STDERR_LOGGING:'1',QT_LOGGING_RULES:'qml.debug=true;*.warning=true;*.critical=true',
            QML_DISK_CACHE_PATH:join(directory,'qmlcache'),XDG_CACHE_HOME:join(directory,'cache'),
            XDG_STATE_HOME:join(directory,'state'),XDG_RUNTIME_DIR:join(directory,'runtime')}});
    const output=result.stdout+result.stderr;
    assert.equal(result.status,0,output);
    assert.match(output,/MIC OSD PASS/);
    assert.doesNotMatch(output,/TypeError|ReferenceError|Binding loop|Failed to get image|Cannot assign/);
} finally { rmSync(directory,{recursive:true,force:true}); }
console.log('Microphone state/IPC and shared OSD layout checks passed');
