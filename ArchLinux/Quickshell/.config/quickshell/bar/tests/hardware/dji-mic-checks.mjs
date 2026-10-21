import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const read=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');
const parser=runInNewContext(read('services/DjiMicBatteryParser.js')+';({parseStatus,batteryIcon})');
const sample={receiver:{level:1,charging:true},transmitters:{tx1:{level:3,charging:true}}};
assert.equal(JSON.stringify(parser.parseStatus(JSON.stringify(sample))),JSON.stringify([{id:'tx1',level:3,charging:true}]));
for (const data of ['bad','null','[]','{}','{"transmitters":[]}',...[-1,0,8,1.5,'1'].map(level=>JSON.stringify({transmitters:{tx1:{level,charging:false}}})),JSON.stringify({transmitters:{tx1:{level:1,charging:1}}})])
    assert.equal(parser.parseStatus(data),null,data);
assert.equal(parser.parseStatus('{"transmitters":{}}').length,0);
assert.equal(parser.parseStatus('{"transmitters":{"tx2":{"level":null,"charging":false}}}')[0].level,null);
assert.equal(new Set(Array.from({length:7},(_,i)=>parser.batteryIcon(i+1))).size,7);
assert.notEqual(parser.batteryIcon(null),parser.batteryIcon(1));
assert.match(read('Config.qml'),/djiMicBattery: false/);
assert.match(read('shell.qml'),/active: root.uses\("djiMicBattery"\) \|\|/);
assert.match(read('widgets/TimeDate.qml'),/DjiMicBattery\s*\{/);
const service=read('services/DjiMicBattery.qml');
const root={queryPending:true,outputFinished:true,errorFinished:true,exitCode:0,timedOut:false,transmitters:[],enabled:true,lastAttemptAt:0};
const context={root,DjiMicBatteryParser:parser,queryOutput:{text:JSON.stringify(sample)},queryError:{text:''},watchdog:{stop(){},restart(){}},queryProcess:{running:false}};
for(const name of ['clearStatus','finishQuery','refresh']) {
    const method=service.match(new RegExp(`function ${name}\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}`));
    assert.ok(method,name);root[name]=runInNewContext(`(function(${method[1]}){${method[2]}})`,context);
}
root.finishQuery();assert.equal(root.available,true);assert.equal(root.transmitters[0].level,3);
root.queryPending=true;root.exitCode=1;root.finishQuery();assert.equal(root.available,false);assert.equal(root.transmitters.length,0);
root.enabled=false;root.refresh();assert.equal(context.queryProcess.running,false,'Disabled module cannot start collector');
root.enabled=true;root.refresh();assert.equal(context.queryProcess.running,true);
const started=root.lastAttemptAt;root.refresh();assert.equal(root.lastAttemptAt,started,'Never overlap queries');
assert.match(service,/interval: 20000/,'Allow ten-second collector deadline and cleanup');
console.log('DJI transmitter parser, failure state, service gating and wiring checks passed');
