import QtQuick
import Quickshell
import Quickshell.Io
import "DjiMicBatteryParser.js" as DjiMicBatteryParser

Scope {
    id: root
    property bool enabled: true
    property bool available: false
    property var transmitters: []
    property string error: "No transmitter reading available"
    property double lastAttemptAt: 0
    property bool queryPending: false
    property bool outputFinished: false
    property bool errorFinished: false
    property int exitCode: -1
    property bool timedOut: false

    function clearStatus(reason) {
        root.available = false;
        root.transmitters = [];
        root.error = reason;
    }
    function refresh(force) {
        const now = Date.now();
        const elapsed = now - root.lastAttemptAt;
        if (!root.enabled || root.queryPending || queryProcess.running || !force && root.lastAttemptAt > 0 && elapsed >= 0 && elapsed < 10000)
            return;
        root.lastAttemptAt = now;
        root.outputFinished = false;
        root.errorFinished = false;
        root.exitCode = -1;
        root.timedOut = false;
        root.queryPending = true;
        watchdog.restart();
        queryProcess.running = true;
    }
    function finishQuery() {
        if (!root.queryPending || !root.outputFinished || !root.errorFinished || root.exitCode < 0)
            return;
        watchdog.stop();
        root.queryPending = false;
        const tx = root.exitCode === 0 && !root.timedOut ? DjiMicBatteryParser.parseStatus(queryOutput.text) : null;
        if (!tx || !tx.length) {
            root.clearStatus(root.timedOut ? "DJI battery query timed out" : root.exitCode !== 0 ? queryError.text.trim().slice(0, 200) || "DJI battery query failed" : tx ? "No transmitter reported" : "Invalid DJI battery response");
            return;
        }
        root.transmitters = tx;
        root.error = "";
        root.available = true;
    }
    Process {
        id: queryProcess
        command: ["python3", Quickshell.shellPath("scripts/dji-mic-battery.py")]
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
        onRunningChanged: {
            if (!running && root.queryPending)
                Qt.callLater(function () {
                    if (!queryProcess.running && root.queryPending && root.exitCode < 0) {
                        root.exitCode = 1;
                        root.outputFinished = true;
                        root.errorFinished = true;
                        root.finishQuery();
                    }
                });
        }
    }
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            root.timedOut = true;
            root.clearStatus("DJI battery query timed out");
            // Keep ownership until exit/streams finish; SIGTERM allows USB cleanup.
            queryProcess.signal(15);
        }
    }
    Timer {
        interval: 60000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
