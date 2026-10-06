import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const api = {};
runInNewContext(readFileSync(new URL('../proton/State.js', import.meta.url), 'utf8'), api);
assert.equal(api.hasCurrentOrNewer({family:'ge',version:[11,7,0]}, [
    {family:'ge',version:[11,7,0],name:'GE-Proton11-7-x86_64'}
]), true);
assert.equal(api.hasCurrentOrNewer({family:'cachyos',version:[20261005,11,0]}, [
    {family:'cachyos',version:[20261005,11,0],name:'proton-cachyos-11.0-20261005-slr-x86_64_v3'}
]), true);
assert.equal(api.hasCurrentOrNewer({family:'ge',version:[11,8,0]}, [
    {family:'ge',version:[11,7,0],name:'GE-Proton11-7-x86_64'}
]), false);
assert.equal(api.hasCurrentOrNewer({family:'cachyos',version:[20261005,11,0]}, [
    {family:'ge',version:[20261005,11,0],name:'wrong-family'}
]), false);
for (const family of ['ge', 'cachyos']) {
    const release = {family, version: family === 'ge' ? [11,7,0] : [20261005,11,0]};
    for (const name of family === 'ge' ? ['GE-Proton11-7', 'GE-Proton11-7-x86_64'] : ['proton-cachyos-11.0-20261005-slr-x86_64_v3']) {
        assert.equal(api.hasCurrentOrNewer(release, [{family, name, version:release.version}]), true);
    }
    const older = [...release.version];
    older[0]--;
    const newer = [...release.version];
    newer[0]++;
    assert.equal(api.hasCurrentOrNewer(release, [{family, version:older}]), false);
    assert.equal(api.hasCurrentOrNewer(release, [{family, version:newer}]), true);
    assert.equal(api.hasCurrentOrNewer(release, []), false);
    assert.equal(api.hasCurrentOrNewer(release, [{family, version:[NaN]}]), false);
    assert.equal(api.hasCurrentOrNewer(release, [{family, version:[]}]), false);
    assert.equal(api.hasCurrentOrNewer({family, version:[]}, [{family, version:release.version}]), false);
}
assert.equal(api.hasCurrentOrNewer(null, []), false);
console.log('Proton GE/CachyOS release-version checks passed');
