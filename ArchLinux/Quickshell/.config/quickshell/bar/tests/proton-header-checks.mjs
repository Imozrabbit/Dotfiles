import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const actionSource = readFileSync(new URL('../proton/Action.qml', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../proton/Manager.qml', import.meta.url), 'utf8');
const expression = actionSource.match(/color: (action\.flat[^\n]+)/)[1];
const color = new Function('action',`return ${expression};`);
const colors = {accent:'accent',secondary:'dim',hoverText:'hover',pressedText:'pressed'};
for (const [flat,hovered,down,expected] of [[true,false,false,'dim'],[true,true,false,'hover'],[true,true,true,'pressed'],[false,false,false,'accent'],[false,true,false,'hover'],[false,true,true,'pressed']])
    assert.equal(color({flat,hovered,down,enabled:true,colors}),expected);
for (const text of ['visible: !action.flat']) assert.ok(actionSource.includes(text));
for (const text of ['id: refreshAction','anchors.rightMargin: 3','text: "↻"','enabled: !root.service.busy','leftPadding: 0','rightPadding: 5','onClicked: root.service.refresh()']) assert.ok(manager.includes(text),text);
assert.ok(!manager.includes('text: "×"'));
console.log('Proton header checks passed');
