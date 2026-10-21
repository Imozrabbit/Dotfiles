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
assert.match(source, /MenuButton\s*\{[\s\S]*?objectName: modelData.id \+ "Dns"/,
    'DNS actions use three shared themed buttons, not per-provider tests');
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
const tint = saved.match(/^    color: (.+)$/m)[1];
const alpha = hovered => runInNewContext(tint, {mouse:{containsMouse:hovered},style:{accent:{r:1,g:1,b:1}},Qt:{rgba:(r,g,b,a)=>a}});
assert.ok(alpha(false)>0 && alpha(true)>alpha(false), 'Saved cards have resting tint and stronger hover tint');
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
        property color error:"#d77"
        property color accent:"#c2a06a"; property color background:"#111"; property color border:"#555"
        property string textFont:"monospace"; property string iconFont:"monospace"
    }
    DnsSettingsPage { id: page; width:366; style:style; profileUuid:"fixture-1"; backend:fakeBackend }
    DnsSettingsPage { id: longPage; width:430; y:800; style:style; profileUuid:"long"; backend:longBackend }
    QtObject { id: longBackend
        property bool busy:false; property bool ready:true; property string configWarning:""
        property var profiles: ({long:{policy:"automatic"}})
        property var providers: [{id:"longone",label:"Long provider one"},{id:"longtwo",label:"Long provider two"}]
        function load(uuid) {}
    }
    QtObject { id: fakeBackend
        property bool busy:false; property bool ready:true; property string configWarning:""
        property var providers: [{id:"quad9",label:"Quad9"},{id:"cloudflare",label:"Cloudflare"},{id:"nextdns",label:"NextDNS",tls:true},{id:"extra",label:"Extra"}]
        property var profiles: ({"fixture-1":{policy:"quad9"},"fixture-2":{policy:"automatic"}})
        property string lastSaved:""
        property string lastTest:""
        function load(uuid) {}
        function save(uuid,policy) { lastSaved=policy; const next=Object.assign({},profiles); next[uuid]={policy:policy}; profiles=next; }
        function test(uuid,provider) { lastTest=uuid+":"+provider; }
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
            const first=find(page,"automaticChoice");
            const second=find(page,"quad9Choice");
            const third=find(page,"cloudflareChoice");
            const fourth=find(page,"nextdnsChoice");
            const fifth=find(page,"extraChoice");
            const position=item=>item.mapToItem(page,0,0);
            const box=first.parent.parent.parent;
            const dnsLabel=box.children.find(child=>child.text === "DNS");
            check(!!dnsLabel && dnsLabel.x===12 && dnsLabel.x+dnsLabel.width<first.parent.parent.x,
                "DNS caption is inside box, beside choices");
            check(Math.abs(box.width-first.parent.parent.x-first.parent.parent.width-4)<1,"DNS box right padding is reduced to four pixels");
            check(first.parent.parent.x-dnsLabel.x-dnsLabel.width<=6,"DNS caption sits close to choices");
            check(Math.abs(box.x+box.width-box.parent.width)<1,"DNS box fills available width");
            check(first.height>=30 && first.parent.parent.x>=8 && first.parent.parent.y>=8,
                "DNS box has roomier rows and internal padding");
            check(Math.abs(position(second).y-position(first).y)<1,"Auto shares a row when space permits");
            const rows=new Set([first,second,third,fourth,fifth].map(item=>item.parent));
            for (const row of rows) {
                const buttons=row.children.filter(item=>item.objectName.endsWith("Choice"));
                check(buttons.length<=3 && row.width<=row.parent.width+1,"Rows fit width and contain at most three choices");
                check(Math.abs(row.x+row.width/2-row.parent.width/2)<1,"Each wrapped row is centered");
            }
            const longAuto=find(longPage,"automaticChoice"), longOne=find(longPage,"longoneChoice"), longTwo=find(longPage,"longtwoChoice");
            check(longAuto.parent===longOne.parent && longTwo.parent!==longOne.parent,"Two long choices fit; third wraps on width, not count alone");
            check(second.width<90 && fourth.width>second.width,"Choice widths follow label length, not equal fixed slots");
            check(first.width<first.parent.parent.width,"Auto hugs its text instead of filling available width");
            check(position(fifth).y>position(first).y && Math.abs(fifth.width-second.width)<1,"Wrapped choices keep text-sized width");
            check(find(page,"automaticChoice").text === "Auto · Network DNS", "Inactive profile describes network DNS, not current VPN");
            page.observedDns={kind:"nextdns",name:"NextDNS",source:"vpn"};
            check(find(page,"automaticChoice").text === "Auto · VPN DNS: NextDNS", "VPN-provided NextDNS is identified");
            check(page.selectedPolicy === "quad9" && !find(page,"automaticChoice").checked,"Observed VPN does not overwrite saved policy");
            page.observedDns={kind:"nextdns",name:"NextDNS",source:"network"};
            check(find(page,"automaticChoice").text === "Auto · Network DNS: NextDNS", "Provider name alone cannot imply VPN");
            page.observedDns={kind:"nextdns",name:"NextDNS",source:"mixed"};
            check(find(page,"automaticChoice").text === "Auto · Mixed DNS", "Mixed DNS sources remain explicit");
            page.observedDns={kind:"unavailable",name:"Unavailable"};
            check(find(page,"automaticChoice").text === "Auto · DNS unavailable", "Unavailable is not claimed as network DNS");
            find(page,"quad9Choice").clicked();
            check(page.selectedPolicy === "quad9", "Quad9 selection");
            check(find(page,"quad9Choice").checked, "Quad9 has visible checked feedback");
            check(find(page,"quad9Choice").text === "Quad9", "Simple Quad9 label");
            find(page,"automaticChoice").clicked();
            check(page.selectedPolicy === "automatic" && find(page,"automaticChoice").checked, "Default checked feedback");
            check(fakeBackend.lastSaved === "" && fakeBackend.profiles["fixture-1"].policy === "quad9","Choosing DNS cannot write profile");
            check(!find(page,"testDns").enabled,"Auto cannot be provider-tested");
            find(page,"cancelDns").clicked();
            check(page.selectedPolicy === "quad9" && fakeBackend.lastSaved === "","Cancel discards pending choice without saving");
            find(page,"automaticChoice").clicked();
            find(page,"confirmDns").clicked();
            check(fakeBackend.lastSaved === "automatic" && !find(page,"confirmDns").enabled,"Confirm saves and clears pending state");
            check(find(page,"automaticChoice").text.startsWith("Auto"), "Short Auto label");
            page.profileUuid="fixture-2";
            check(page.selectedPolicy === "automatic", "Changing profile displays its saved policy");
            check(find(page,"cloudflareChoice") !== null,"Configured providers appear dynamically");
            find(page,"cloudflareChoice").clicked();
            check(fakeBackend.lastSaved === "automatic" && page.selectedPolicy === "cloudflare", "Provider selection remains pending");
            const testAction=find(page,"testDns");
            check(testAction.compact && testAction.height===24,"Provider tests use compact secondary actions");
            check(testAction.kind === "ghost" && testAction.color.a === 0,"Test action is transparent/themed");
            testAction.clicked();
            check(fakeBackend.lastTest === "fixture-2:cloudflare" && fakeBackend.lastSaved === "automatic","Test probes pending choice without saving");
            fakeBackend.profiles=Object.assign({},fakeBackend.profiles,{"fixture-2":{policy:"automatic",message:"Test completed"}});
            check(page.selectedPolicy === "cloudflare","Test feedback cannot discard pending choice");
            find(page,"nextdnsChoice").clicked();
            find(page,"testDns").clicked();
            check(fakeBackend.lastTest === "fixture-2:nextdns", "TLS provider uses existing test action");
            fakeBackend.busy=true;
            for (const name of ["confirmDns","testDns","cancelDns"]) check(!find(page,name).enabled,"Actions disabled during operations");
            fakeBackend.busy=false;
            const providers=fakeBackend.providers;
            fakeBackend.providers=providers.filter(provider=>provider.id!=="nextdns");
            check(!find(page,"confirmDns").enabled && !find(page,"testDns").enabled,"Removed pending provider cannot be saved or tested");
            fakeBackend.providers=providers;
            find(page,"confirmDns").clicked();
            check(fakeBackend.lastSaved === "nextdns" && page.selectedPolicy === "nextdns", "Confirm saves TLS provider ID");
            find(page,"quad9Choice").clicked();
            page.profileUuid="fixture-1";
            check(page.selectedPolicy === "automatic","Changing profiles discards pending choice");
            find(page,"quad9Choice").clicked();
            page.visible=false; page.visible=true;
            check(page.selectedPolicy === "automatic","Closing/reopening discards pending choice");
            page.isHome=true;
            check(page.homeLocked && !find(page,"cloudflareChoice").enabled,"Home has no selectable providers");
            const homeStatus=find(page,"homeDnsStatus");
            check(homeStatus && homeStatus.visible && homeStatus.parent===box && box.visible,"Home status shares bordered DNS box");
            check(homeStatus.text === "Router DNS (automatic)" && !find(page,"automaticChoice").visible,"Home shows read-only status, not choices");
            for (const name of ["confirmDns","testDns","cancelDns"]) check(!find(page,name).enabled,"Home cannot mutate or test provider choices");
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
