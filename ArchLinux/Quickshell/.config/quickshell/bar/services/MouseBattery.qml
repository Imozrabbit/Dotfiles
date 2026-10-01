import QtQuick
import Quickshell
import Quickshell.Io

import "MouseBatteryParser.js" as MouseBatteryParser

Scope {
    id: root

    property bool available: false
    property int percentage: -1
    property bool charging: false
    property string connection: ""
    property string error: "No reading available"
    property double lastAttemptAt: 0
    property bool queryPending: false
    property bool outputFinished: false
    property bool errorFinished: false
    property int exitCode: -1

    function clearStatus(reason) {
        root.available = false;
        root.percentage = -1;
        root.charging = false;
        root.connection = "";
        root.error = reason;
    }

    function refresh() {
        const now = Date.now();
        if (root.queryPending || queryProcess.running || root.lastAttemptAt > 0 && now - root.lastAttemptAt < 10000)
            return;
        root.lastAttemptAt = now;
        root.outputFinished = false;
        root.errorFinished = false;
        root.exitCode = -1;
        root.queryPending = true;
        watchdog.restart();
        queryProcess.running = true;
    }

    function finishQuery() {
        if (!root.queryPending || !root.outputFinished || !root.errorFinished || root.exitCode < 0)
            return;
        watchdog.stop();
        root.queryPending = false;
        const status = root.exitCode === 0 ? MouseBatteryParser.parseStatus(queryOutput.text) : null;
        if (!status) {
            root.clearStatus(root.exitCode === 0 ? "Invalid mouse battery response" : queryError.text.trim().slice(0, 200) || "Mouse query failed");
            return;
        }
        root.percentage = status.battery;
        root.charging = status.charging;
        root.connection = status.connection;
        root.error = "";
        root.available = true;
    }

    Process {
        id: queryProcess
        command: ["python3", Quickshell.shellPath("scripts/wlmouse.py")]
        stdout: StdioCollector {
            id: queryOutput
            onStreamFinished: {
                root.outputFinished = true;
                root.finishQuery();
            }
        }
        stderr: StdioCollector {
            id: queryError
            onStreamFinished: {
                root.errorFinished = true;
                root.finishQuery();
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.exitCode = exitCode;
            root.finishQuery();
        }
        // qmllint enable signal-handler-parameters
    }

    Timer {
        id: watchdog
        interval: 5000
        repeat: false
        onTriggered: {
            root.queryPending = false;
            root.clearStatus("Mouse query timed out");
            queryProcess.running = false;
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
