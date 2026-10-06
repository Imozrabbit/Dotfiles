import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../proton/Manager.qml', import.meta.url), 'utf8');
const expression = source.match(/height: (Math\.min\(650[^\n]+)/)?.[1];
assert.ok(expression?.includes('popupContent.implicitHeight'), 'Popup follows active content height');
const height = new Function('popupContent', 'root', 'anchors', `return ${expression};`);
const content = { implicitHeight: 350, anchors: { topMargin: 13, bottomMargin: 13 } };
assert.equal(height(content, { height: 1080 }, { bottomMargin: 40 }), 376);
assert.equal(height({ ...content, implicitHeight: 900 }, { height: 1080 }, { bottomMargin: 40 }), 650);
assert.equal(height(content, { height: 300 }, { bottomMargin: 40 }), 250);
assert.ok(source.includes('tabContents.implicitHeight'), 'Tab card follows active tab content');
assert.ok(readFileSync(new URL('../../proton/widgets/Confirmation.qml', import.meta.url), 'utf8').includes('confirmationContent.implicitHeight + 56'), 'Confirmation has room within cap');
console.log('Proton height checks passed');
