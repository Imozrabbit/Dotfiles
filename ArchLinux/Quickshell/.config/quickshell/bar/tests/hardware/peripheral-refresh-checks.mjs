import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const read=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');
for (const name of ['MouseBattery','DjiMicBattery']) {
    const service=read('services/'+name+'.qml');
    const refresh=service.match(/function refresh\(([^)]*)\) \{([\s\S]*?)\n    \}/);
    assert.ok(refresh);
    const root={enabled:true,queryPending:false,lastAttemptAt:99000};
    const queryProcess={running:false};let starts=0;
    const call=runInNewContext(`(function(${refresh[1]}){${refresh[2]}})`,{root,queryProcess,Date:{now:()=>100000},watchdog:{restart(){starts++;}}});
    call(false);assert.equal(starts,0,name+': hover respects cooldown');
    call(true);assert.equal(starts,1,name+': click bypasses cooldown');
    call(true);assert.equal(starts,1,name+': force cannot overlap pending query');
    root.queryPending=false;call(true);assert.equal(starts,1,name+': force cannot overlap running process');
    queryProcess.running=false;
    if(name==='DjiMicBattery') { root.enabled=false;call(true);assert.equal(starts,1,'Disabled DJI cannot be forced');root.enabled=true; }
    call(true);assert.equal(starts,2,name+': subsequent deliberate click can refresh');
    root.clearStatus=()=>{};queryProcess.signal=()=>{};
    const timeout=service.slice(service.indexOf('id: watchdog')).match(/onTriggered: \{([\s\S]*?)\n        \}/);
    assert.ok(timeout);
    runInNewContext(timeout[1],{root,queryProcess});
    assert.equal(root.queryPending,true,name+': timeout must retain ownership until streams drain');
    call(true);assert.equal(starts,2,name+': click cannot reuse timed-out process before completion');
    const widget=read('widgets/'+name+'.qml');
    assert.match(widget,/signal refreshRequested\(bool force\)/);
    assert.match(widget,/acceptedButtons: Qt.LeftButton/);
    assert.match(widget,/onTapped: root.refreshRequested\(true\)/);
    assert.match(widget,/root.refreshRequested\(false\)/);
    assert.match(widget,/cursorShape: Qt.PointingHandCursor/);
}
const time=read('widgets/TimeDate.qml'), window=read('BarWindow.qml');
for(const name of ['mouse','dji']) {
    assert.match(time,new RegExp(`signal ${name}RefreshRequested\\(bool force\\)`));
    assert.match(time,new RegExp(`onRefreshRequested: force => root\\.${name}RefreshRequested\\(force\\)`));
    assert.match(window,new RegExp(`root\\.${name==='mouse'?'mouseBattery':'djiMicBattery'}Service\\.refresh\\(force\\)`));
}
console.log('Mouse/DJI click refresh, cooldown bypass, overlap guards and force routing checks passed');
