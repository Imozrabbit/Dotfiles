pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property bool panelOpen: false
    property string scriptPath: ""
    readonly property string resolvedScriptPath: {
        if (root.scriptPath.startsWith("~/") && root.scriptPath.length > 2) {
            const home = Quickshell.env("HOME");
            return home ? home + root.scriptPath.slice(1) : "";
        }
        return root.scriptPath.startsWith("/") && root.scriptPath.length > 1 ? root.scriptPath : "";
    }
    readonly property bool observing: root.enabled && root.panelOpen && root.resolvedScriptPath !== ""
    property var state: null
    readonly property bool available: root.enabled && root.state !== null && root.actionError === ""
    readonly property bool active: root.available && root.state === "on"
    readonly property bool busy: root.operation !== ""
    readonly property bool actionBusy: root.busy && root.operation !== "status"
    readonly property string details: !root.available ? "Unavailable" : root.active ? "Everyone on LAN" : "Tailscale only"
    property string actionError: ""
    property string statusError: ""
    readonly property string lastError: root.actionError || root.statusError

    property int generation: 0
    property int commandGeneration: -1
    property string operation: ""
    property bool refreshPending: false
    property bool queryInvalid: false
    property bool timedOut: false
    property string queryOutput: ""
    property string commandError: ""
    property int resultCode: -1

    function resetObservation(): void {
        root.generation++;
        root.state = null;
        root.actionError = "";
        root.statusError = root.resolvedScriptPath === "" ? "LocalSend helper path unavailable" : "";
        root.refreshPending = false;
        Qt.callLater(root.refresh);
    }

    function refresh(): void {
        if (!root.observing)
            return;
        if (root.busy) {
            root.refreshPending = true;
            return;
        }
        root.run("status");
    }

    function run(operation: string): void {
        root.operation = operation;
        root.commandGeneration = root.generation;
        root.refreshPending = false;
        root.queryInvalid = false;
        root.timedOut = false;
        root.queryOutput = "";
        root.commandError = "";
        root.resultCode = -1;
        const action = operation === "on" || operation === "off" ? operation : "status";
        command.exec({
            command: ["sudo", "-n", "--", root.resolvedScriptPath, action],
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function toggle(): bool {
        if (!root.observing || !root.available || root.actionBusy)
            return false;
        root.actionError = "";
        if (root.operation === "status")
            root.operation = "before";
        else
            root.run("before");
        return true;
    }

    function finishCommand(): void {
        if (root.operation === "" || command.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        const current = root.commandGeneration === root.generation;
        root.operation = "";
        if (!current) {
            root.refresh();
            return;
        }
        const succeeded = root.resultCode === 0 && !root.timedOut;
        if (operation === "on" || operation === "off") {
            if (!succeeded) {
                root.actionError = root.commandError.trim() || "LocalSend request failed (exit " + root.resultCode + ")";
                root.state = null;
                console.warn(root.actionError);
            }
            root.run("after");
            return;
        }
        const value = root.queryOutput.trim();
        const state = succeeded && !root.queryInvalid && (value === "on" || value === "off") ? value : null;
        root.queryOutput = "";
        root.state = state;
        root.statusError = state === null ? root.commandError.trim() || "LocalSend status unavailable" : "";
        if (operation === "status" && state !== null)
            root.actionError = "";
        if (operation === "before" && state !== null) {
            root.run(state === "on" ? "off" : "on");
            return;
        }
        if (root.refreshPending)
            root.refresh();
    }

    onEnabledChanged: root.resetObservation()
    onPanelOpenChanged: root.resetObservation()
    onResolvedScriptPathChanged: root.resetObservation()
    Component.onCompleted: Qt.callLater(root.refresh)

    Timer {
        interval: 5000
        repeat: true
        running: root.observing
        onTriggered: {
            if (!root.busy)
                root.refresh();
        }
    }

    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: {
            root.timedOut = true;
            root.commandError = "LocalSend command timed out";
            command.running = false;
        }
    }

    Process {
        id: command
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            // Failed starts have no exited signal; let normal exit data drain first.
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.operation === "on" || root.operation === "off" || root.queryInvalid)
                    return;
                if (root.queryOutput.length + data.length > 16) {
                    root.queryInvalid = true;
                    root.queryOutput = "";
                } else {
                    root.queryOutput += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (!root.timedOut)
                    root.commandError = (root.commandError + data).slice(-1024);
            }
        }
    }
}
