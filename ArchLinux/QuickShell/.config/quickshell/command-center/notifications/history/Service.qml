pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

Scope {
    id: root

    readonly property var entries: store.document.entries.map(entry => ({
                id: entry.id,
                appName: entry.appName,
                summary: entry.summary,
                body: entry.body,
                time: Qt.formatDateTime(new Date(entry.receivedAt), "MMM d, HH:mm"),
                appIcon: (entry.appIcon.startsWith("/") && !entry.appIcon.startsWith("//")) || entry.appIcon.startsWith("file:///") ? entry.appIcon : ""
            }))
    readonly property bool busy: store.busy || root.savingDocument !== null || root.saveScheduled
    readonly property string lastError: store.lastError || root.listenerError || root.frameError
    readonly property bool running: monitor.running
    property var pending: null
    property var savingDocument: null
    property bool saveScheduled: false
    property string listenerError: ""
    property string frameError: ""
    property string frameBuffer: ""
    property bool discardingFrame: false
    property int listenerExitCode: -1

    function synchronize(): void {
        if (!root.saveScheduled)
            return;
        root.saveScheduled = false;
        if (!store.ready || store.busy || root.savingDocument !== null || root.pending === store.document)
            return;
        root.savingDocument = root.pending;
        if (!store.save(root.savingDocument))
            root.savingDocument = null;
    }

    function scheduleSave(): void {
        root.saveScheduled = true;
        Qt.callLater(root.synchronize);
    }

    function retainUnsaved(entries: var): var {
        const arrivals = root.pending ? root.pending.entries.filter(entry => entry.id >= store.document.nextId) : [];
        if (arrivals.length === 0 && entries === store.document.entries)
            return store.document;
        return {
            version: 1,
            nextId: root.pending ? root.pending.nextId : store.document.nextId,
            entries: arrivals.concat(entries)
        };
    }

    function removeEntries(entries: var): bool {
        if (!store.ready || root.busy || entries.length === store.document.entries.length)
            return false;
        root.pending = root.retainUnsaved(entries);
        root.scheduleSave();
        return true;
    }

    function clear(id: var): bool {
        return root.removeEntries(store.document.entries.filter(entry => entry.id !== id));
    }

    function clearGroup(appName: string): bool {
        return root.removeEntries(store.document.entries.filter(entry => entry.appName !== appName));
    }

    function clearAll(): bool {
        return root.removeEntries([]);
    }

    function accept(line: string): void {
        if (!root.pending)
            return;
        const entry = Protocol.parseNotification(line, root.pending.nextId, Date.now());
        if (!entry)
            return;
        // shortcut: record each Notify request; correlate daemon replies if replacement deduplication is needed.
        root.pending = {
            version: 1,
            nextId: entry.id + 1,
            entries: [entry].concat(root.pending.entries)
        };
        root.frameError = "";
        root.scheduleSave();
    }

    function readChunk(data: string): void {
        let start = 0;
        while (start < data.length) {
            const end = data.indexOf("\n", start);
            const stop = end < 0 ? data.length : end;
            if (!root.discardingFrame) {
                if (root.frameBuffer.length + stop - start > 4194304) {
                    root.frameBuffer = "";
                    root.discardingFrame = true;
                    root.frameError = "Notification history skipped an oversized request";
                } else {
                    root.frameBuffer += data.slice(start, stop);
                }
            }
            if (end < 0)
                return;
            if (!root.discardingFrame)
                root.accept(root.frameBuffer);
            root.frameBuffer = "";
            root.discardingFrame = false;
            start = end + 1;
        }
    }

    function startMonitor(): void {
        if (!store.ready || monitor.running)
            return;
        reconnect.stop();
        root.listenerExitCode = -1;
        // Parent-death signal also stops monitoring when Quickshell receives SIGTERM/SIGKILL.
        monitor.exec({
            command: ["setpriv", "--pdeathsig=KILL", "--", "busctl", "--user", "--json=short", "--match=type='method_call',interface='org.freedesktop.Notifications',member='Notify',path='/org/freedesktop/Notifications'", "monitor"],
            environment: {
                LC_ALL: "C",
                NOTIFY_SOCKET: null
            }
        });
    }

    Store {
        id: store
        onReadyChanged: {
            if (ready) {
                root.pending = store.document;
                Qt.callLater(root.startMonitor);
            }
        }
        onSaved: {
            if (root.pending === root.savingDocument)
                root.pending = store.document;
            root.savingDocument = null;
            if (root.pending !== store.document)
                root.scheduleSave();
        }
        onSaveFailed: {
            root.pending = root.retainUnsaved(store.document.entries);
            root.savingDocument = null;
            root.saveScheduled = false;
        }
    }

    Timer {
        id: reconnect
        interval: 10000
        onTriggered: root.startMonitor()
    }

    Process {
        id: monitor
        onStarted: root.listenerError = ""
        onExited: (exitCode, exitStatus) => root.listenerExitCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (!running && store.ready) {
                root.frameBuffer = "";
                root.discardingFrame = false;
                root.listenerError = "Notification history listener unavailable (exit " + root.listenerExitCode + "); retrying in 10 seconds";
                reconnect.restart();
            }
        }
        stdout: SplitParser {
            // Native line buffering is unbounded; assemble limited frames above.
            splitMarker: ""
            onRead: data => root.readChunk(data)
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
