pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property bool available: false
    property real value: 1
    property string device: ""
    property string actionError: ""
    property string statusError: ""
    readonly property string lastError: root.actionError || root.statusError
    readonly property bool busy: root.operation !== "" || root.pendingValue !== null || root.refreshPending

    property var pendingValue: null
    property string pendingDevice: ""
    property bool refreshPending: false
    property bool queryInvalid: false
    property string operation: ""
    property string queryOutput: ""
    property string commandError: ""
    property int resultCode: -1

    function parseReading(text: string): var {
        const fields = text.trim().split(",");
        if (fields.length !== 5 || !/^[A-Za-z0-9_.:-]{1,200}$/.test(fields[0]) || fields[1] !== "backlight" || !/^\d+$/.test(fields[2]) || !/^(100|[0-9]{1,2})%$/.test(fields[3]) || !/^\d+$/.test(fields[4]))
            return null;
        const current = Number(fields[2]);
        const maximum = Number(fields[4]);
        if (!Number.isSafeInteger(current) || !Number.isSafeInteger(maximum) || maximum <= 0 || current > maximum)
            return null;
        return {
            device: fields[0],
            value: Math.max(1, current / maximum * 100)
        };
    }

    function refresh(): void {
        // A live read satisfies polling; only invalidated reads need a replacement.
        if (!root.enabled || (root.operation === "query" && !root.queryInvalid))
            return;
        root.refreshPending = true;
        workDelay.restart();
    }

    function setValue(value: real): bool {
        if (!root.available || !root.enabled || !isFinite(value))
            return false;
        root.pendingValue = Math.round(Math.max(1, Math.min(100, value)));
        root.pendingDevice = root.device;
        root.actionError = "";
        workDelay.restart();
        return true;
    }

    function run(operation: string, args: var): void {
        root.operation = operation;
        root.resultCode = -1;
        root.commandError = "";
        command.exec({
            command: ["brightnessctl"].concat(args),
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function work(): void {
        if (!root.enabled || root.operation !== "")
            return;
        if (root.refreshPending) {
            root.refreshPending = false;
            root.queryInvalid = false;
            root.queryOutput = "";
            root.run("query", ["--class=backlight", "--machine-readable", "info"]);
        } else if (root.pendingValue !== null) {
            const value = root.pendingValue;
            root.pendingValue = null;
            if (root.available && root.pendingDevice === root.device)
                root.run("set", ["--class=backlight", "--device=" + root.device, "--min-value=1", "set", value + "%"]);
        }
    }

    function finishCommand(): void {
        if (root.operation === "" || command.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        root.operation = "";
        if (operation === "query") {
            const reading = root.enabled && root.resultCode === 0 && !root.queryInvalid ? root.parseReading(root.queryOutput) : null;
            root.queryOutput = "";
            root.available = reading !== null;
            if (reading) {
                if (root.device !== reading.device)
                    root.pendingValue = null;
                root.device = reading.device;
                root.value = reading.value;
                root.statusError = "";
            } else {
                root.pendingValue = null;
                root.statusError = root.commandError.trim() || "Brightness status unavailable";
            }
        } else {
            if (root.resultCode !== 0) {
                root.pendingValue = null;
                root.actionError = root.commandError.trim() || "Brightness request failed (exit " + root.resultCode + ")";
                console.warn(root.actionError);
            }
            root.refreshPending = root.enabled;
        }
        if (root.refreshPending || root.pendingValue !== null)
            workDelay.restart();
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.available = false;
            root.queryInvalid = true;
            root.pendingValue = null;
            root.refreshPending = false;
            workDelay.stop();
        }
    }
    Component.onCompleted: root.refresh()

    Timer {
        id: workDelay
        interval: 50
        onTriggered: root.work()
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: {
            root.commandError = "Brightness command timed out";
            command.running = false;
        }
    }

    Process {
        id: command
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            // Failed starts have no exited signal; wait for normal exit output to drain.
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.operation !== "query" || root.queryInvalid)
                    return;
                if (root.queryOutput.length + data.length > 1024) {
                    root.queryInvalid = true;
                    root.queryOutput = "";
                } else {
                    root.queryOutput += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.commandError = (root.commandError + data).slice(0, 1024)
        }
    }
}
