pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Protocol.js" as Protocol

Scope {
    id: root
    readonly property var document: store.document
    readonly property bool ready: root.initialized
    readonly property bool busy: store.busy || root.savingDocument !== null || root.saveScheduled
    readonly property string lastError: store.lastError || root.localError
    readonly property var nextId: root.pending ? root.pending.nextId : store.document.nextId
    property var pending: null
    property var savingDocument: null
    property var clearBase: []
    property var clearTargets: []
    property var automaticRemovals: []
    property bool initialized: false
    property bool handoverLoaded: false
    property bool saveScheduled: false
    property string localError: ""
    signal cleared(var targets)

    PersistentProperties {
        id: handover
        reloadableId: "command-center-native-archive"
        property string pendingJson: ""
        property string clearJson: ""
        onLoaded: {
            root.handoverLoaded = true;
            if (handover.clearJson !== "") {
                try {
                    const value = JSON.parse(handover.clearJson);
                    root.clearBase = value.base;
                    root.clearTargets = value.targets;
                    root.automaticRemovals = value.automaticRemovals || [];
                } catch (_) {
                    root.localError = "Notification history reload state invalid";
                }
            }
            root.initialize();
        }
    }

    function ordered(entries: var): var {
        return entries.slice().sort((a, b) => (b.updatedAt ?? b.receivedAt) - (a.updatedAt ?? a.receivedAt) || b.id - a.id);
    }

    function initialize(): void {
        if (root.initialized || !root.handoverLoaded || !store.ready)
            return;
        const cached = handover.pendingJson ? Protocol.decodeHistory(handover.pendingJson) : null;
        if (cached) {
            const entries = cached.entries.slice();
            for (const entry of store.document.entries) {
                const index = entries.findIndex(value => value.id === entry.id);
                if (index >= 0 && (entry.updatedAt ?? entry.receivedAt) > (entries[index].updatedAt ?? entries[index].receivedAt))
                    entries[index] = entry;
                else if (index < 0 && entry.id >= cached.nextId)
                    entries.push(entry);
            }
            const merged = {
                version: 1,
                nextId: Math.max(cached.nextId, store.document.nextId),
                entries: root.ordered(entries)
            };
            root.pending = JSON.stringify(merged) === JSON.stringify(store.document) ? store.document : merged;
        } else {
            root.pending = store.document;
        }
        root.initialized = true;
        if (root.pending !== store.document)
            root.scheduleSave();
        else if (root.clearTargets.length)
            Qt.callLater(root.completeClear);
    }

    function cacheClear(): void {
        handover.clearJson = root.clearTargets.length ? JSON.stringify({
            base: root.clearBase,
            targets: root.clearTargets,
            automaticRemovals: root.automaticRemovals
        }) : "";
    }

    onPendingChanged: {
        if (root.pending !== null && root.handoverLoaded)
            handover.pendingJson = JSON.stringify(root.pending);
    }

    function scheduleSave(): void {
        root.saveScheduled = true;
        Qt.callLater(root.synchronize);
    }

    function synchronize(): void {
        root.saveScheduled = false;
        if (!root.ready || store.busy || root.savingDocument !== null || root.pending === store.document)
            return;
        root.savingDocument = root.pending;
        if (!store.save(root.savingDocument))
            root.savingDocument = null;
    }

    function upsert(entry: var): bool {
        if (!root.ready || !root.pending || root.nextId >= Number.MAX_SAFE_INTEGER)
            return false;
        const entries = root.pending.entries.filter(value => value.id !== entry.id).concat([entry]);
        const next = Protocol.decodeHistory(JSON.stringify({
            version: 1,
            nextId: Math.max(root.nextId, entry.id + 1),
            entries: root.ordered(entries)
        }));
        if (!next) {
            root.localError = "Notification history update invalid";
            return false;
        }
        root.localError = "";
        root.pending = next;
        root.scheduleSave();
        return true;
    }

    function remove(ids: var): bool {
        if (!root.ready || !root.pending)
            return false;
        if (root.clearTargets.length) {
            root.automaticRemovals = root.automaticRemovals.concat(ids);
            root.cacheClear();
        }
        const entries = root.pending.entries.filter(entry => !ids.includes(entry.id));
        if (entries.length === root.pending.entries.length)
            return false;
        root.pending = {
            version: 1,
            nextId: root.nextId,
            entries
        };
        root.scheduleSave();
        return true;
    }

    function isClearing(id: var, revision: var): bool {
        return root.clearTargets.some(target => target.id === id && target.revision === revision);
    }

    function clear(targets: var): bool {
        if (!root.ready || root.busy)
            return false;
        const entries = root.pending.entries.filter(entry => targets.some(target => target.id === entry.id && target.revision === (entry.revision ?? 0)));
        if (!entries.length)
            return false;
        root.clearBase = entries;
        root.clearTargets = entries.map(entry => ({
                    id: entry.id,
                    revision: entry.revision ?? 0
                }));
        root.automaticRemovals = [];
        root.cacheClear();
        root.pending = {
            version: 1,
            nextId: root.nextId,
            entries: root.pending.entries.filter(entry => !root.isClearing(entry.id, entry.revision ?? 0))
        };
        root.scheduleSave();
        return true;
    }

    function completeClear(): void {
        const targets = root.clearTargets;
        root.clearBase = [];
        root.clearTargets = [];
        root.automaticRemovals = [];
        root.cacheClear();
        if (targets.length)
            root.cleared(targets);
    }

    Store {
        id: store
        onReadyChanged: root.initialize()
        onSaved: {
            if (root.pending === root.savingDocument)
                root.pending = store.document;
            root.savingDocument = null;
            root.completeClear();
            if (root.pending !== store.document)
                root.scheduleSave();
        }
        onSaveFailed: {
            if (root.pending && root.clearTargets.length) {
                const entries = root.pending.entries.slice();
                for (const entry of root.clearBase) {
                    if (!root.automaticRemovals.includes(entry.id) && !entries.some(value => value.id === entry.id))
                        entries.push(entry);
                }
                root.pending = {
                    version: 1,
                    nextId: root.nextId,
                    entries: root.ordered(entries)
                };
            }
            root.clearBase = [];
            root.clearTargets = [];
            root.automaticRemovals = [];
            root.cacheClear();
            root.savingDocument = null;
            root.saveScheduled = false;
        }
    }
}
