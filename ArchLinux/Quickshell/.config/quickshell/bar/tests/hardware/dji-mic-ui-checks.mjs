import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync,copyFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
const directory=mkdtempSync('/tmp/opencode/dji-mic-ui-');
try {
    for (const name of ['MouseBattery','DjiMicBattery']) {
        const source=readFileSync(new URL('../../widgets/'+name+'.qml',import.meta.url),'utf8')
            .replace(/^import qs.core as Core\n/m,'').replace('Core.Theme','var')
            .replace('../services/DjiMicBatteryParser.js','DjiMicBatteryParser.js');
        writeFileSync(join(directory,name+'.qml'),source);
    }
    copyFileSync(new URL('../../services/DjiMicBatteryParser.js',import.meta.url),join(directory,'DjiMicBatteryParser.js'));
    writeFileSync(join(directory,'SystemStatTooltip.qml'),'import QtQuick\nItem { property var anchorItem; property string heading; property var rows; property var theme }');
    mkdirSync(join(directory,'runtime'),{mode:0o700});
    writeFileSync(join(directory,'Check.qml'),`import QtQuick
import QtQuick.Layouts
Window {
    width:400; height:100; visible:true
    QtObject { id: theme; property color timeDateColor:"white"; property string fontFamily:"monospace"; property int timeDateFontSize:14 }
    RowLayout { id: row
        MouseBattery { id: mouse; theme:theme; mouseName:"Mouse"; available:true; percentage:75; charging:false; connection:"wireless"; error:"" }
        DjiMicBattery { id: mic; theme:theme; available:true; transmitters:[{id:"tx1",level:1,charging:false}]; error:"" }
    }
    Timer { interval:100; running:true; onTriggered: {
        const mouseText=mouse.children.find(child=>child.text!==undefined);
        const micText=mic.children.find(child=>child.text!==undefined);
        if (!(mic.implicitWidth<mouse.implicitWidth) || mic.implicitHeight!==mouse.implicitHeight
            || micText.color!==mouseText.color || micText.font.pixelSize!==mouseText.font.pixelSize
            || micText.text.includes("TX1") || micText.text.includes("%")) throw new Error("DJI chip must be compact and match mouse theme");
        if (micText.text.includes("")) throw new Error("Unexpected charging marker");
        mic.transmitters=[{id:"tx1",level:7,charging:true}];
        if (!micText.text.includes("")) throw new Error("Missing charging marker");
        mic.available=false;
        if (!micText.text.includes("N/A")) throw new Error("Missing unavailable state");
        console.log("DJI UI PASS"); Qt.quit();
    }}
}`);
    const result=spawnSync('qml6',[join(directory,'Check.qml')],{encoding:'utf8',timeout:10000,
        env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software',QT_FORCE_STDERR_LOGGING:'1',QT_LOGGING_RULES:'qml.debug=true;*.warning=true;*.critical=true',
            QML_DISK_CACHE_PATH:join(directory,'qmlcache'),XDG_CACHE_HOME:join(directory,'cache'),XDG_STATE_HOME:join(directory,'state'),XDG_RUNTIME_DIR:join(directory,'runtime')}});
    const output=result.stdout+result.stderr;
    assert.equal(result.status,0,output);assert.match(output,/DJI UI PASS/);
    assert.doesNotMatch(output,/TypeError|ReferenceError|Binding loop|Cannot assign/);
} finally { rmSync(directory,{recursive:true,force:true}); }
console.log('DJI/mouse content width, shared styling, charging and unavailable UI checks passed');
