pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property bool panelOpen: false
    property int temperature: 4500
    readonly property bool validTemperature: root.temperature >= 1000 && root.temperature <= 20000
    readonly property bool observing: root.enabled && root.panelOpen && root.validTemperature
    property var state: null
    readonly property bool available: root.enabled && root.validTemperature && root.state !== null && root.actionError === ""
    readonly property bool active: root.available && root.state === false
    readonly property bool busy: root.operation !== ""
    readonly property string details: !root.available ? "Unavailable" : root.active ? "On" : "Off"
    property string actionError: ""
    property string statusError: ""
    readonly property string lastError: root.actionError || root.statusError || (root.validTemperature ? "" : "Temperature must be an integer from 1000 to 20000K")

    property int generation: 0
    property int commandGeneration: -1
    property int requestedTemperature: 4500
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
        root.statusError = "";
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
        const args = operation === "on" ? ["temperature", String(root.requestedTemperature)] : operation === "off" ? ["identity", "true"] : ["identity", "get"];
        command.exec({
            command: ["hyprctl", "hyprsunset"].concat(args),
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function toggle(): bool {
        if (!root.observing || !root.available || root.busy)
            return false;
        root.actionError = "";
        // Settings edits must not redirect an already accepted click.
        root.requestedTemperature = root.temperature;
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
        const succeeded = root.resultCode === 0 && !root.timedOut && !root.queryInvalid;
        const value = root.queryOutput.trim();
        root.queryOutput = "";
        if (operation === "on" || operation === "off") {
            if (!succeeded || value !== "ok") {
                root.actionError = root.commandError.trim() || "Hyprsunset request failed or was rejected";
                root.state = null;
            }
            root.run("after");
            return;
        }
        const state = succeeded && (value === "true" || value === "false") ? value === "true" : null;
        root.state = state;
        root.statusError = state === null ? root.commandError.trim() || "Hyprsunset status unavailable" : "";
        if (operation === "status" && state !== null)
            root.actionError = "";
        if (operation === "before" && state !== null) {
            root.run(state ? "on" : "off");
            return;
        }
        if (root.refreshPending)
            root.refresh();
    }

    onEnabledChanged: root.resetObservation()
    onPanelOpenChanged: root.resetObservation()
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
            root.commandError = "Hyprsunset command timed out";
            command.signal(9); // SIGKILL: IPC clients must not outlive the timeout.
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
                if (root.queryInvalid)
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
