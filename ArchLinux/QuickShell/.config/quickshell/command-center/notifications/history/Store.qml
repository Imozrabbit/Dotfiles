pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

Scope {
    id: root

    readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/quickshell/notification-history.json"
    readonly property string directory: root.historyPath.slice(0, root.historyPath.lastIndexOf("/"))
    readonly property var document: root.committed
    readonly property bool ready: root.initialized
    readonly property bool busy: root.loading || root.operation !== "" || root.snapshot !== null
    property string lastError: ""
    property var committed: Protocol.emptyHistory()
    property var snapshot: null
    property string payload: ""
    property bool initialized: false
    property bool loading: true
    property bool directoryCreated: false
    property string operation: ""
    property string commandOutput: ""
    property string temporaryPath: ""
    property string failure: ""
    property int resultCode: -1
    signal saved
    signal saveFailed

    function fail(message: string): void {
        root.lastError = message;
        console.warn(message);
        root.loading = false;
        root.snapshot = null;
        root.payload = "";
        root.saveFailed();
    }

    function run(operation: string, args: var): void {
        root.operation = operation;
        root.commandOutput = "";
        root.resultCode = -1;
        worker.stdinEnabled = operation === "write";
        worker.exec({
            command: args,
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function save(document: var): bool {
        if (!root.ready || root.busy)
            return false;
        const payload = JSON.stringify(document);
        const snapshot = Protocol.decodeHistory(payload);
        if (!snapshot)
            return false;
        root.snapshot = snapshot;
        root.payload = payload;
        root.lastError = "";
        root.failure = "";
        if (root.directoryCreated)
            root.createTemporary();
        else
            root.run("mkdir", ["mkdir", "-p", "--", root.directory]);
        return true;
    }

    function createTemporary(): void {
        root.run("temporary", ["mktemp", "--tmpdir=" + root.directory, ".notification-history.XXXXXXXXXX"]);
    }

    function finishCommand(): void {
        if (root.operation === "" || worker.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        root.operation = "";
        if (operation === "inspect") {
            if (root.resultCode < 0) {
                root.fail("Notification history permissions could not be checked; file left unchanged");
                return;
            }
            if (root.resultCode === 0) {
                const output = root.commandOutput.trim();
                const mode = /^[0-9a-f]+$/i.test(output) ? parseInt(output, 16) : 0;
                if ((mode & 61440) !== 32768 || (mode & 63) !== 0) {
                    root.fail("Notification history must be a regular owner-only file (mode 0600)");
                    return;
                }
            }
            historyFile.path = root.historyPath;
            return;
        }
        if (operation === "cleanup") {
            root.temporaryPath = "";
            root.fail(root.failure + (root.resultCode === 0 ? "" : "; temporary-file cleanup failed"));
            return;
        }
        if (root.resultCode !== 0) {
            root.failure = "Notification history " + operation + " failed; previous history preserved";
            if (root.temporaryPath !== "")
                root.run("cleanup", ["rm", "-f", "--", root.temporaryPath]);
            else
                root.fail(root.failure);
            return;
        }
        if (operation === "mkdir") {
            root.directoryCreated = true;
            root.createTemporary();
        } else if (operation === "temporary") {
            const path = root.commandOutput.trim();
            const prefix = root.directory + "/.notification-history.";
            if (!path.startsWith(prefix) || !/^[A-Za-z0-9]{10}$/.test(path.slice(prefix.length))) {
                root.fail("Notification history temporary-file creation returned an invalid path");
                return;
            }
            root.temporaryPath = path;
            root.run("write", ["dd", "of=" + path, "conv=fsync", "status=none"]);
        } else if (operation === "write") {
            root.run("rename", ["mv", "--force", "--no-target-directory", "--", root.temporaryPath, root.historyPath]);
        } else if (operation === "rename") {
            // shortcut: one writer per user; add locking if independent instances must share history.
            root.temporaryPath = "";
            root.committed = root.snapshot;
            root.snapshot = null;
            root.payload = "";
            root.saved();
        }
    }

    Component.onCompleted: {
        if (!Quickshell.env("HOME").startsWith("/"))
            root.fail("Notification history requires an absolute HOME directory");
        else
            root.run("inspect", ["stat", "--format=%f", "--", root.historyPath]);
    }

    FileView {
        id: historyFile
        printErrors: false
        onLoaded: {
            const document = Protocol.decodeHistory(text());
            if (!document) {
                root.fail("Notification history is invalid or unsupported; file left unchanged");
                return;
            }
            root.committed = document;
            root.loading = false;
            root.initialized = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.loading = false;
                root.initialized = true;
            } else {
                root.fail("Notification history could not be read; file left unchanged");
            }
        }
    }

    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: worker.signal(9)
    }

    Process {
        id: worker
        onStarted: {
            if (root.operation === "write") {
                worker.write(root.payload);
                worker.stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            // Failed starts have no exited signal; allow normal exit data to drain first.
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.commandOutput.length + data.length > 8192)
                    worker.signal(9);
                else
                    root.commandOutput += data;
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
