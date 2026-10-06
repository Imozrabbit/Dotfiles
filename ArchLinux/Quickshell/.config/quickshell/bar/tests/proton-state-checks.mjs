import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const api = {};
runInNewContext(readFileSync(new URL('../proton/State.js', import.meta.url), 'utf8'), api);
const snapshot = { installations: [], geVersions: [], currentGeVersion: null, releases: {},
    package: { state: 'notInstalled', installedVersion: null, availableVersion: '1.3', messages: [] },
    blockers: [], locations: { compatibilityToolsDir: '/a', umuConfigPath: '/b', sandboxCompatibilityToolsDir: '/c' },
    messages: { updates: [], installed: [], package: [], selection: [] } };
const event = (type, data, id = 'request') => JSON.stringify({ id, type, data });
assert.ok(api.parseEvent(event('snapshot', snapshot), 'request'));
for (const line of ['garbage', '{}', event('snapshot', {}, 'request'), event('snapshot', snapshot, 'stale')])
    assert.equal(api.parseEvent(line, 'request'), null);
for (const fraction of [-1, 2, '1'])
    assert.equal(api.parseEvent(event('progress', { stage: 'Download', fraction, downloadedBytes: 0, totalBytes: null }), 'request'), null);
assert.ok(api.parseEvent(event('progress', { stage: 'Extract', fraction: null, downloadedBytes: 0, totalBytes: null }), 'request'));
assert.equal(api.parseEvent(event('result', { status: 'success', area: 'updates', messages: [{ severity: 'error', text: 9 }], snapshot }), 'request'), null);
let state = api.emptyState();
state = api.applyEvent(state, api.parseEvent(event('snapshot', snapshot), 'request'));
assert.equal(state.snapshot.package.state, 'notInstalled');
let inspected = api.beginRequest(state);
const local = { ...snapshot, package: { state: 'unavailable', installedVersion: null, availableVersion: null, messages: [] } };
inspected = api.applyEvent(inspected, api.parseEvent(event('snapshot', local), 'request'));
assert.equal(inspected.snapshot.package.state, 'notInstalled', 'Local inspection preserves checked package status');
let refreshed = api.beginRequest(state, true);
refreshed = api.applyEvent(refreshed, api.parseEvent(event('snapshot', local), 'request'));
assert.equal(refreshed.snapshot.package.state, 'unavailable', 'Full refresh replaces stale package status');
state = api.applyEvent(state, api.parseEvent(event('result', { status: 'partial', area: 'updates', messages: [{ severity: 'warning', text: 'Retained' }], snapshot }), 'request'));
assert.equal(state.messages.updates[0].text, 'Retained');
assert.equal(state.finished, true);
const committed = state;
state = api.applyEvent(state, api.parseEvent(event('result', { status: 'success', area: 'updates', messages: [], snapshot: null }), 'request'));
assert.equal(state, committed, 'Duplicate terminal events ignored');
console.log('Proton state checks passed');
