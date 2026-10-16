import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const source=readFileSync(new URL('../../network/wifi/services/WifiDnsService.qml',import.meta.url),'utf8');
const root={busy:true,action:'save',requestUuid:'a',requestConfig:'{}',configJson:'{}',readQueue:[],ready:true,
    configurePending:false,profiles:{a:{policy:'quad9'}},drain(){},run(...args){this.ran=args;},
    update(uuid,data){this.profiles[uuid]=data;}};
const context={root,query:{running:false},watchdog:{stop(){}},Qt:{callLater(){}},output:{text:''},errors:{text:'Test failed'}};
for (const name of ['load','drain','finish']) {
    const method=source.match(new RegExp(`function ${name}\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}`));
    assert.ok(method,name);
    root[name]=runInNewContext(`(function(${method[1]}){${method[2]}})`,context);
}
root.load('b'); root.load('b');
assert.equal(JSON.stringify(root.readQueue),'["b"]','Busy reads queue once instead of disappearing');
root.busy=false; root.drain();
assert.equal(JSON.stringify(root.ran),'["b",""]');
root.busy=true; root.action='test'; root.exitCode=1; root.outputDone=true; root.errorDone=true;
root.finish();
assert.equal(root.profiles.a.policy,'quad9','A test failure cannot erase saved DNS policy');
assert.equal(root.profiles.a.error,true);
const timeout=source.slice(source.indexOf('id: watchdog')).match(/onTriggered: \{([\s\S]*?)\n        \}/)[1];
root.busy=true; root.action='read'; root.timedOut=false; context.query.running=true;
runInNewContext(timeout,context);
assert.equal(root.busy,true,'Timeout must retain process ownership until streams drain');
assert.equal(root.timedOut,true);
assert.equal(context.query.running,false);
root.finish();
assert.equal(root.busy,false);
assert.match(root.profiles.a.message,/timed out/);
assert.match(source,/onConfigJsonChanged:/,'Configuration validation tracks values, not object identity');
assert.doesNotMatch(source,/property bool saving|function enforce\(/,'No redundant action flag or separate enforcement queue');
console.log('DNS request queue, test failure and config reload checks passed');
