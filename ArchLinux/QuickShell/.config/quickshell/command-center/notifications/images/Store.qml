pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../native/Policy.js" as Policy

Scope {
    id: root
    property bool authoritative: false
    readonly property string directory: Quickshell.env("HOME") + "/.local/state/quickshell/notification-thumbnails"
    readonly property bool busy: root.current !== null || root.operation !== "" || root.queue.length > 0 || root.cleanupRequested
    property string lastError: ""
    property var job: null
    property var queue: []
    property var current: null
    property var references: []
    property var garbage: []
    property bool cleanupRequested: false
    property string operation: ""
    property string output: ""
    property bool invalidOutput: false
    property int resultCode: -1
    signal completed(string token, string name, bool success)

    function owned(name: string): bool {
        return /^notification-[A-Za-z0-9]{10}\.png$/.test(name);
    }

    function request(token: string, source: string): bool {
        if (!root.authoritative || !Quickshell.env("HOME").startsWith("/") || Policy.localImage(source) === "")
            return false;
        if (root.current?.token === token || root.queue.some(value => value.token === token))
            return false;
        root.queue = root.queue.concat([
            {
                kind: "capture",
                token,
                source,
                path: "",
                created: false
            }
        ]);
        Qt.callLater(root.pump);
        return true;
    }

    function reconcile(references: var): void {
        root.references = references.filter(name => typeof name === "string" && root.owned(name));
        if (!root.authoritative)
            return;
        root.cleanupRequested = true;
        Qt.callLater(root.pump);
    }

    function cancel(token: string): void {
        root.queue = root.queue.filter(value => value.token !== token);
        if (root.current?.kind !== "capture" || root.current.token !== token)
            return;
        root.current.cancelled = true;
        if (root.operation === "") {
            root.job = null;
            captureTimeout.stop();
            if (root.current.path)
                root.run("discard", ["rm", "-f", "--", root.current.path]);
            else
                root.done(false, "");
        }
    }

    function pump(): void {
        if (!root.authoritative || root.current || root.operation !== "")
            return;
        if (root.queue.length) {
            root.current = root.queue[0];
            root.queue = root.queue.slice(1);
        } else if (root.cleanupRequested) {
            root.cleanupRequested = false;
            root.current = {
                kind: "gc",
                created: false
            };
        } else {
            return;
        }
        root.run("inspect", ["stat", "--format=%f", "--", root.directory]);
    }

    function run(operation: string, args: var): void {
        root.operation = operation;
        root.output = "";
        root.invalidOutput = false;
        root.resultCode = -1;
        worker.exec({
            command: args,
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function done(success: bool, name: string): void {
        const current = root.current;
        root.current = null;
        root.job = null;
        captureTimeout.stop();
        if (current?.kind === "capture")
            root.completed(current.token, name, success);
        Qt.callLater(root.pump);
    }

    function fail(message: string): void {
        root.lastError = message;
        if (root.current?.kind === "capture" && root.current.path) {
            root.job = null;
            root.run("discard", ["rm", "-f", "--", root.current.path]);
        } else {
            root.done(false, "");
        }
    }

    function finish(token: string, success: bool): void {
        if (!root.job || root.job.token !== token)
            return;
        captureTimeout.stop();
        if (!success || !root.authoritative) {
            root.fail("Notification image preview unavailable");
        } else {
            const name = root.job.path.slice(root.directory.length + 1);
            root.lastError = "";
            root.done(true, name);
        }
    }

    function removeBatch(): void {
        if (!root.garbage.length) {
            root.done(true, "");
            return;
        }
        const batch = root.garbage.slice(0, 128);
        root.garbage = root.garbage.slice(128);
        root.run("remove", ["rm", "-f", "--"].concat(batch.map(name => root.directory + "/" + name)));
    }

    function finishCommand(): void {
        if (root.operation === "" || worker.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        root.operation = "";
        if (operation === "inspect" && root.resultCode === 1 && !root.current.created) {
            if (root.current.kind === "gc") {
                root.done(true, "");
            } else {
                root.current.created = true;
                root.run("mkdir", ["mkdir", "-p", "--mode=700", "--", root.directory]);
            }
            return;
        }
        if (operation === "discard") {
            if (root.resultCode !== 0)
                root.lastError += "; temporary preview cleanup failed";
            root.done(false, "");
            return;
        }
        if (root.resultCode !== 0 || root.invalidOutput) {
            root.fail("Notification thumbnail " + operation + " failed");
            return;
        }
        if (root.current.cancelled && operation !== "temporary") {
            root.done(false, "");
            return;
        }
        if (operation === "mkdir") {
            root.run("inspect", ["stat", "--format=%f", "--", root.directory]);
        } else if (operation === "inspect") {
            const value = root.output.trim();
            const mode = /^[0-9a-f]+$/i.test(value) ? parseInt(value, 16) : 0;
            if ((mode & 61440) !== 16384 || (mode & 63) !== 0) {
                root.fail("Notification thumbnail directory must be a private regular directory");
            } else if (root.current.kind === "capture") {
                root.run("temporary", ["mktemp", "--tmpdir=" + root.directory, "--suffix=.png", "notification-XXXXXXXXXX"]);
            } else {
                root.run("list", ["find", root.directory, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "notification-*.png", "-printf", "%f\n"]);
            }
        } else if (operation === "temporary") {
            const path = root.output.trim();
            if (!path.startsWith(root.directory + "/") || !root.owned(path.slice(root.directory.length + 1))) {
                root.fail("Notification thumbnail temporary path invalid");
                return;
            }
            root.current.path = path;
            if (root.current.cancelled) {
                root.run("discard", ["rm", "-f", "--", path]);
                return;
            }
            root.job = {
                token: root.current.token,
                source: root.current.source,
                path
            };
            captureTimeout.restart();
        } else if (operation === "list") {
            root.garbage = root.output.split("\n").filter(name => root.owned(name) && !root.references.includes(name));
            root.removeBatch();
        } else if (operation === "remove") {
            root.removeBatch();
        }
    }

    onAuthoritativeChanged: {
        if (!root.authoritative) {
            root.queue = [];
            root.cleanupRequested = false;
        }
    }

    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: worker.signal(9)
    }
    Timer {
        id: captureTimeout
        interval: 3000
        onTriggered: root.fail("Notification thumbnail capture timed out")
    }
    Process {
        id: worker
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.invalidOutput)
                    return;
                const maximum = root.operation === "list" ? 8388608 : 8192;
                if (root.output.length + data.length > maximum) {
                    root.invalidOutput = true;
                    root.output = "";
                    worker.signal(9);
                } else {
                    root.output += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
