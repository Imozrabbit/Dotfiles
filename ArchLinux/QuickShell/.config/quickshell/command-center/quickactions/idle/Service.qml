pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property var state: null
    readonly property bool available: root.enabled && root.state !== null
    readonly property bool active: root.available && ["active", "reloading", "refreshing"].includes(root.state)
    readonly property bool transitioning: ["activating", "deactivating", "reloading", "refreshing"].includes(root.state)
    readonly property bool busy: root.requesting || root.transitioning
    readonly property string details: !root.available ? "Unavailable" : root.state === "activating" ? "Starting" : root.state === "deactivating" ? "Stopping" : root.state === "reloading" ? "Reloading" : root.state === "refreshing" ? "Refreshing" : root.state === "failed" ? "Failed" : root.active ? "On" : "Off"
    property string actionError: ""
    property string statusError: ""
    readonly property string lastError: root.actionError || root.statusError

    property bool requesting: false
    property bool pendingToggle: false
    property bool refreshPending: false
    property bool queryForAction: false
    property bool queryCompletesAction: false
    property bool queryInvalid: false
    property string operation: ""
    property string queryOutput: ""
    property string commandError: ""
    property int resultCode: -1

    function parseState(text: string): var {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || !lines.includes("LoadState=loaded"))
            return null;
        const value = lines.find(line => line.startsWith("ActiveState="));
        const state = value ? value.slice("ActiveState=".length) : "";
        return ["active", "inactive", "failed", "activating", "deactivating", "reloading", "refreshing"].includes(state) ? state : null;
    }

    function refresh(): void {
        if (!root.enabled)
            return;
        root.refreshPending = true;
        refreshDelay.restart();
    }

    function run(operation: string): void {
        root.operation = operation;
        root.resultCode = -1;
        root.commandError = "";
        const args = operation === "query" ? ["--no-pager", "show", "--property=LoadState,ActiveState"] : ["--no-ask-password", "--no-block", operation];
        command.exec({
            command: ["systemctl", "--user"].concat(args, ["idle-inhibit.service"]),
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function query(): void {
        if (!root.enabled || !root.refreshPending || root.operation !== "")
            return;
        root.refreshPending = false;
        root.queryForAction = root.pendingToggle;
        root.pendingToggle = false;
        root.queryCompletesAction = root.requesting && !root.queryForAction;
        root.queryInvalid = false;
        root.queryOutput = "";
        root.run("query");
    }

    function toggle(): bool {
        if (!root.available || root.busy)
            return false;
        root.requesting = true;
        root.pendingToggle = true;
        root.actionError = "";
        root.refresh();
        return true;
    }

    function finishCommand(): void {
        if (root.operation === "" || command.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        root.operation = "";
        if (operation === "query") {
            const state = root.resultCode === 0 && root.enabled && !root.queryInvalid ? root.parseState(root.queryOutput) : null;
            if (!root.requesting && state !== root.state)
                root.actionError = "";
            root.state = state;
            root.queryOutput = "";
            root.statusError = state === null ? "Idle inhibitor status unavailable" : "";
            if (root.queryForAction && root.requesting) {
                if (state === null || root.transitioning)
                    root.requesting = false;
                else
                    root.run(root.active ? "stop" : "start");
            } else if (root.queryCompletesAction) {
                root.requesting = false;
            }
        } else {
            if (root.requesting && root.resultCode !== 0) {
                root.actionError = root.commandError.trim() || "Idle inhibitor request failed (exit " + root.resultCode + ")";
                console.warn(root.actionError);
            }
            root.refresh();
        }
        if (root.refreshPending)
            refreshDelay.restart();
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.state = null;
            root.queryInvalid = true;
            root.pendingToggle = false;
            root.requesting = false;
            root.refreshPending = false;
            refreshDelay.stop();
        }
    }
    Component.onCompleted: root.refresh()

    Timer {
        id: refreshDelay
        interval: 100
        onTriggered: root.query()
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: {
            root.commandError = "Idle inhibitor command timed out";
            command.running = false;
        }
    }

    Process {
        id: command
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            // Failed starts have no exited signal; defer until normal exit data is drained.
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.operation !== "query" || root.queryInvalid)
                    return;
                if (root.queryOutput.length + data.length > 256) {
                    root.queryInvalid = true;
                    root.queryOutput = "";
                } else {
                    root.queryOutput += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.commandError = (root.commandError + data).slice(-1024)
        }
    }
}
