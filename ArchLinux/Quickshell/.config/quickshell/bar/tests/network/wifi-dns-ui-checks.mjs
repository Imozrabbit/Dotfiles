import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, cpSync, mkdtempSync, mkdirSync, rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';

const page = new URL('../../network/wifi/ui/DnsSettingsPage.qml', import.meta.url);
let source = '';
try { source = readFileSync(page, 'utf8'); } catch (_) {}
assert.ok(source, 'DNS selection preview component must exist');
assert.doesNotMatch(source, /RadioButton|ButtonGroup/, 'DNS choice uses compact segments, not radio circles');
assert.match(source, /RowLayout\s*\{/, 'DNS label and segments share a row');
assert.match(source, /horizontalAlignment: Text.AlignHCenter/, 'Preview note is centered');
assert.doesNotMatch(source, /9\.9\.9\.9|2620:|Preview selection|Preview first-connection/,
    'Selector must not show server addresses or preview actions');
assert.doesNotMatch(source, /\bProcess\s*\{|nmcli|FileView|XMLHttpRequest/, 'UI phase cannot read/write real DNS');
const card = readFileSync(new URL('../../network/wifi/ui/WifiMenuCard.qml',import.meta.url),'utf8');
assert.match(card, /property string expandedDnsKey: ""/, 'One accordion state for connected and saved cards');
assert.doesNotMatch(card, /function openDns|id: dnsPage/, 'No separate DNS editor');
const toggle=card.match(/function toggleDns\(key\) \{([\s\S]*?)\n    \}/)[1];
const root={controller:{isBusy:false},expandedDnsKey:""};
for (const [key,expected] of [['saved:a','saved:a'],['connected:b','connected:b'],['connected:b','']]) {
    runInNewContext(`(function(key){${toggle}})(key)`,{root,key});
    assert.equal(root.expandedDnsKey,expected);
}
const saved = readFileSync(new URL('../../network/wifi/ui/SavedNetworkRow.qml',import.meta.url),'utf8');
assert.match(saved,/onClicked: root.toggleRequested\(\)/, 'Card click only expands');
assert.match(saved,/text: "Connect"/, 'Connection action remains explicit');
assert.match(saved,/DnsSettingsPage\s*\{/, 'DNS is inside saved card');
const summary=readFileSync(new URL('../../network/wifi/ui/ConnectionSummary.qml',import.meta.url),'utf8');
assert.match(summary,/DnsSettingsPage\s*\{/, 'DNS is inside connected card');
for (const component of [saved, summary])
    assert.match(component, /isHome: root.isHome/);
assert.doesNotMatch(source,/resetPreview|defaultPolicy|UI only/,'Production UI has no preview-only policy fallback');
assert.match(card, /isHome: root.homeSsids.includes\(savedRow.ssid\)/);
assert.match(card, /isHome: root.homeSsids.includes\(root.controller.currentSsid\)/);
const controller=readFileSync(new URL('../../network/wifi/WifiController.qml',import.meta.url),'utf8');
const refreshed=controller.match(/function onRefreshed\(generation\) \{([\s\S]*?)\n        \}/)[1];
for (const awaiting of [false,true]) for (const known of [false,true]) for (const visible of [false,true]) {
    let prompts=0;
    const state={newDnsAwaitingStatus:awaiting,activeConnectionUuid:'fixture',currentSsid:'Hotspot',newDnsSsid:'Hotspot',
        currentIp:'',connectionReady:true,knownDnsUuids:known?['fixture']:[],dnsPromptUuid:'',menuVisible:visible,
        wifiTogglePending:false,homeSsids:[],dnsChoiceRequested:()=>prompts++};
    runInNewContext(`(function(generation){${refreshed}})(1)`,{root:state});
    assert.equal(prompts, Number(awaiting && !known && visible), 'Only a new panel-created profile can prompt');
}
const directory = mkdtempSync('/tmp/opencode/wifi-dns-ui-');
try {
    cpSync(page, join(directory, 'DnsSettingsPage.qml'));
    cpSync(new URL('../../network/wifi/ui/SavedNetworkRow.qml',import.meta.url),join(directory,'SavedNetworkRow.qml'));
    cpSync(new URL('../../network/wifi/ui/controls/', import.meta.url), join(directory, 'controls'), {recursive:true});
    mkdirSync(join(directory,'runtime'),{mode:0o700});
    writeFileSync(join(directory,'Check.qml'), `import QtQuick
import QtQuick.Controls
Window {
    id: window
    property int connectionRequests: 0
    width:390; height:700; visible:true
    QtObject { id: style
        property color foreground:"#ddd"; property color muted:"#888"; property color success:"#8fb7ab"
        property color accent:"#c2a06a"; property color background:"#111"; property color border:"#555"
        property string textFont:"monospace"; property string iconFont:"monospace"
    }
    DnsSettingsPage { id: page; width:366; style:style; profileUuid:"fixture-1"; backend:fakeBackend }
    QtObject { id: fakeBackend
        property bool busy:false; property bool ready:true; property string configWarning:""
        property var providers: [{id:"quad9",label:"Quad9"},{id:"cloudflare",label:"Cloudflare"}]
        property var profiles: ({"fixture-1":{policy:"quad9"},"fixture-2":{policy:"automatic"}})
        property string lastSaved:""
        function load(uuid) {}
        function save(uuid,policy) { lastSaved=policy; const next=Object.assign({},profiles); next[uuid]={policy:policy}; profiles=next; }
        function test(uuid,provider) {}
    }
    SavedNetworkRow { id: saved; width:366; y:300; style:style; ssid:"Saved"; uuid:"fixture-saved"; name:"Saved"; isEnterprise:false; isBusy:false; dnsBackend:fakeBackend
        onToggleRequested: expanded = !expanded
        onClicked: window.connectionRequests++
    }
    function find(item,name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const result=find(child,name); if(result) return result; }
        return null;
    }
    function check(ok,message) { if (!ok) throw new Error(message); }
    Timer { interval:100; running:true; onTriggered: {
        try {
            check(page.selectedPolicy === "quad9", "Saved Quad9 policy displayed");
            check(page.implicitHeight > 0, "Preview has layout height");
            find(page,"quad9Choice").clicked();
            check(page.selectedPolicy === "quad9", "Quad9 selection");
            check(find(page,"quad9Choice").checked, "Quad9 has visible checked feedback");
            check(find(page,"quad9Choice").text === "Quad9", "Simple Quad9 label");
            find(page,"automaticChoice").clicked();
            check(page.selectedPolicy === "automatic" && find(page,"automaticChoice").checked, "Default checked feedback");
            check(find(page,"automaticChoice").text === "Default", "Simple Default label");
            page.profileUuid="fixture-2";
            check(page.selectedPolicy === "automatic", "Changing profile displays its saved policy");
            check(find(page,"cloudflareChoice") !== null,"Configured providers appear dynamically");
            find(page,"cloudflareChoice").clicked();
            check(fakeBackend.lastSaved === "cloudflare" && page.selectedPolicy === "cloudflare", "Custom provider selection saves ID");
            page.isHome=true;
            check(page.homeLocked && !find(page,"cloudflareChoice").enabled,"Home has no selectable providers");
            check(saved.height === 35, "Saved card initially collapsed");
            saved.toggleRequested();
            check(saved.expanded && saved.height > 35 && window.connectionRequests === 0, "Expansion cannot connect");
            saved.toggleRequested();
            check(!saved.expanded && saved.height === 35, "Card collapses");
            console.log("DNS UI PASS"); Qt.quit();
        } catch(error) { console.error(error); Qt.exit(1); }
    }}
}`);
    const result=spawnSync('qml6',[join(directory,'Check.qml')],{encoding:'utf8',timeout:10000,
        env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software',QT_FORCE_STDERR_LOGGING:'1',QT_LOGGING_RULES:'qml.debug=true;*.warning=true;*.critical=true',
            QML_DISK_CACHE_PATH:join(directory,'qmlcache'),XDG_CACHE_HOME:join(directory,'cache'),
            XDG_STATE_HOME:join(directory,'state'),XDG_RUNTIME_DIR:join(directory,'runtime')}});
    const output=result.stdout+result.stderr;
    assert.equal(result.status,0,output);
    assert.ok(output.includes('DNS UI PASS'),output);
    assert.doesNotMatch(output,/TypeError|ReferenceError|Binding loop|Cannot assign/);
} finally { rmSync(directory,{recursive:true,force:true}); }
console.log('Wi-Fi DNS UI preview checks passed');
