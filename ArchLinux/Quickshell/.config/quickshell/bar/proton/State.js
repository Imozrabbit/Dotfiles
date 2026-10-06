function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function text(value, max) { return typeof value === "string" && value.length <= (max || 4096) && !value.includes("\0"); }
function messages(value) {
    return Array.isArray(value) && value.length <= 200 && value.every(message => object(message)
        && ["info", "success", "warning", "error"].includes(message.severity) && text(message.text, 1000));
}
function version(value) { return Array.isArray(value) && value.length > 0 && value.length <= 4 && value.every(part => Number.isSafeInteger(part) && part >= 0); }
function identity(value) {
    return object(value) && Number.isSafeInteger(value.device) && Number.isSafeInteger(value.inode)
        && text(value.modified, 30) && /^\d+$/.test(value.modified) && /^[a-f0-9]{64}$/.test(value.metadata);
}
function installation(value) {
    return object(value) && text(value.name, 128) && ["ge", "cachyos"].includes(value.family)
        && version(value.version) && text(value.path) && value.path.startsWith("/")
        && typeof value.umuSelected === "boolean" && identity(value.identity);
}
function release(value) {
    return object(value) && ["ge", "cachyos"].includes(value.family) && text(value.name, 128)
        && text(value.tag, 128) && version(value.version) && text(value.archiveName, 256)
        && text(value.archiveUrl, 8192) && text(value.checksumUrl, 8192);
}
function snapshot(value) {
    return object(value) && Array.isArray(value.installations) && value.installations.length <= 2000
        && value.installations.every(installation) && Array.isArray(value.geVersions)
        && value.geVersions.length <= 2000 && value.geVersions.every(name => text(name, 128)
            && value.installations.some(item => item.name === name && item.family === "ge"))
        && (value.currentGeVersion === null || value.geVersions.includes(value.currentGeVersion))
        && object(value.releases) && Object.keys(value.releases).every(key => ["ge", "cachyos"].includes(key)
            && release(value.releases[key]) && value.releases[key].family === key)
        && object(value.package) && ["upToDate", "updateAvailable", "notInstalled", "unavailable"].includes(value.package.state)
        && [value.package.installedVersion, value.package.availableVersion].every(v => v === null || text(v, 128))
        && messages(value.package.messages) && Array.isArray(value.blockers) && value.blockers.length <= 200
        && value.blockers.every(v => text(v, 1000)) && object(value.locations)
        && ["compatibilityToolsDir", "umuConfigPath", "sandboxCompatibilityToolsDir"].every(key => text(value.locations[key]) && value.locations[key].startsWith("/"))
        && object(value.messages) && ["updates", "installed", "package", "selection"].every(area => messages(value.messages[area]));
}
function confirmation(value) {
    return object(value) && ["install", "remove"].includes(value.action)
        && (value.action === "install" ? release(value.target) : installation(value.target))
        && Array.isArray(value.cleanupCandidates) && value.cleanupCandidates.length <= 2000
        && value.cleanupCandidates.every(installation) && /^[a-f0-9]{64}$/.test(value.fingerprint);
}
function parseEvent(line, requestId) {
    if (!text(line, 2 * 1024 * 1024)) return null;
    let event;
    try { event = JSON.parse(line); } catch (_) { return null; }
    if (!object(event) || event.id !== requestId || !object(event.data)) return null;
    const value = event.data;
    if (event.type === "snapshot" && snapshot(value)) return event;
    if (event.type === "confirmation" && confirmation(value)) return event;
    if (event.type === "progress" && text(value.stage, 256)
        && (value.fraction === null || typeof value.fraction === "number" && isFinite(value.fraction) && value.fraction >= 0 && value.fraction <= 1)
        && Number.isSafeInteger(value.downloadedBytes) && value.downloadedBytes >= 0
        && (value.totalBytes === null || Number.isSafeInteger(value.totalBytes) && value.totalBytes >= value.downloadedBytes)) return event;
    if (event.type === "result" && ["success", "partial", "blocked", "error"].includes(value.status)
        && ["updates", "installed", "package", "selection"].includes(value.area)
        && messages(value.messages) && (value.snapshot === null || snapshot(value.snapshot))) return event;
    return null;
}
function emptyState() {
    return { snapshot: null, confirmation: null, progress: null, finished: false, replaceRemote: false,
        messages: { updates: [], installed: [], package: [], selection: [] } };
}
function beginRequest(state, replaceRemote) {
    return { snapshot: state.snapshot, confirmation: null, progress: null, finished: false, messages: state.messages, replaceRemote: replaceRemote === true };
}
function mergeSnapshot(state, value) {
    if (!state.snapshot || state.replaceRemote) return value;
    const next = Object.assign({}, value);
    next.releases = Object.assign({}, state.snapshot.releases, value.releases);
    if (value.package.state === "unavailable" && value.package.messages.length === 0)
        next.package = state.snapshot.package;
    return next;
}
function applyEvent(state, event) {
    if (!event || state.finished) return state;
    const next = Object.assign({}, state);
    if (event.type === "snapshot") next.snapshot = mergeSnapshot(state, event.data);
    else if (event.type === "confirmation") next.confirmation = event.data;
    else if (event.type === "progress") next.progress = event.data;
    else if (event.type === "result") {
        next.finished = true;
        if (event.data.snapshot) next.snapshot = mergeSnapshot(state, event.data.snapshot);
        next.messages = Object.assign({}, state.messages);
        next.messages[event.data.area] = event.data.messages;
    }
    return next;
}

function compareVersions(left, right) {
    if (!version(left) || !version(right)) return -1;
    for (let index = 0; index < Math.max(left.length, right.length); index++) {
        const a = left[index] ?? 0;
        const b = right[index] ?? 0;
        if (a !== b) return a > b ? 1 : -1;
    }
    return 0;
}
function hasCurrentOrNewer(release, installations) {
    return object(release) && Array.isArray(installations) && installations.some(item => object(item)
        && item.family === release.family && compareVersions(item.version, release.version) >= 0);
}
