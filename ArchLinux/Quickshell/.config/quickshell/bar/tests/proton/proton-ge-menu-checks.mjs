import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../../proton/widgets/GeSelector.qml', import.meta.url), 'utf8');
const body = source.match(/function toggleMenu\(\) \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(body);
const toggle = new Function('root', 'geMenu', body);
const menu = { visible: false, open() { this.visible = true; }, close() { this.visible = false; } };
toggle({enabled:true,versions:['GE']},menu); assert.equal(menu.visible,true);
toggle({enabled:true,versions:['GE']},menu); assert.equal(menu.visible,false);
toggle({enabled:true,versions:[]},menu); assert.equal(menu.visible,false);
const above = new Function('currentIndex','versions',`return ${source.match(/visibleRowsAbove: ([^\n]+)/)[1]};`);
const below = new Function('currentIndex','versions','visibleRowsAbove',`return ${source.match(/visibleRowsBelow: ([^\n]+)/)[1]};`);
for (const [length,index,expected] of [[2,0,[0,1]],[2,1,[1,0]],[10,0,[0,2]],[10,5,[1,1]],[10,9,[2,0]]]) {
    const versions = Array(length), a = above(index,versions);
    assert.deepEqual([a,below(index,versions,a)],expected);
}
for (const text of ['Tumbler {','wrap: false','parent: root','Popup.CloseOnPressOutsideParent','root.height - 1','color: geFieldSurface.color','text: wheelEntry.modelData','text: "➜"','root.selectRequested(wheelEntry.modelData)']) assert.ok(source.includes(text),text);
assert.ok(!source.includes('onCurrentIndexChanged:'));
console.log('Proton GE menu checks passed');
