pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property bool observing: root.enabled
    readonly property bool monitorRunning: monitor.running
    signal connectionsChanged
    property var state: null
    property string actionError: ""
    property string statusError: ""
    readonly property bool available: root.enabled && root.state !== null
    readonly property bool active: root.available && root.state === true
    readonly property string details: !root.available ? "Unavailable" : root.active ? "On" : "Off"
    // Alias reads native state immediately, including within the launch event turn.
    property alias busy: confirmation.running
    readonly property string lastError: root.actionError || root.statusError

    property bool refreshPending: false
    property string queryOutput: ""
    property bool queryInvalid: false

    function startMonitor(): void {
        if (!root.observing || monitor.running)
            return;
        monitor.exec({
            command: ["/bin/sh", "-c", "exec nmcli monitor"],
            environment: {
                LC_ALL: "C"
            }
        });
    }

    function refresh(): void {
        if (!root.enabled)
            return;
        root.refreshPending = true;
        refreshDelay.restart();
    }

    function query(): void {
        if (!root.refreshPending || statusQuery.running || !root.enabled)
            return;
        root.refreshPending = false;
        root.queryOutput = "";
        root.queryInvalid = false;
        statusQuery.exec({
            command: ["/bin/sh", "-c", "exec nmcli -t -f NETWORKING general status"],
            environment: {
                LC_ALL: "C"
            }
        });
    }

    function toggle(): bool {
        if (confirmation.running || !root.available)
            return false;
        root.actionError = "";
        confirmation.exec({
            command: ["/bin/sh", Quickshell.shellDir + "/quickactions/network/confirm.sh"],
            environment: {
                COMMAND_CENTER_PID: String(Quickshell.processId)
            }
        });
        return true;
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.state = null;
            root.queryInvalid = true;
            root.refreshPending = false;
            refreshDelay.stop();
            statusQuery.running = false;
        }
    }
    onObservingChanged: {
        if (root.observing)
            root.startMonitor();
        else
            monitor.running = false;
    }
    Component.onCompleted: {
        root.startMonitor();
        root.refresh();
    }

    Timer {
        id: refreshDelay
        interval: 100
        onTriggered: root.query()
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.observing && (!monitor.running || (root.enabled && !root.available))
        onTriggered: {
            root.startMonitor();
            root.refresh();
        }
    }

    Process {
        id: monitor
        onExited: {
            root.refresh();
            root.connectionsChanged();
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: {
                root.refresh();
                root.connectionsChanged();
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }

    Process {
        id: statusQuery
        onExited: (exitCode, exitStatus) => {
            const value = root.queryOutput.trim();
            const valid = exitCode === 0 && exitStatus === 0 && !root.queryInvalid && root.enabled && (value === "enabled" || value === "disabled");
            root.state = valid ? value === "enabled" : null;
            root.queryOutput = "";
            root.statusError = valid ? "" : "Network status unavailable";
            if (root.refreshPending)
                refreshDelay.restart();
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
            onRead: {}
        }
    }

    Process {
        id: confirmation
        workingDirectory: Quickshell.shellDir
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.actionError = "Network action failed (exit " + exitCode + ")";
                console.warn(root.actionError);
            }
            root.refresh();
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: {}
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
