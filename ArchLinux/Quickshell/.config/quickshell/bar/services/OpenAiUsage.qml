import QtQuick
import Quickshell
import Quickshell.Io

import "OpenAiUsage.js" as Usage

Scope {
    id: root

    required property date currentDate
    property var snapshot: null
    property bool available: false
    property string error: "No quota reading available"
    property double lastAttemptAt: 0
    property bool queryPending: false
    property bool outputFinished: false
    property bool errorFinished: false
    property int exitCode: -1
    readonly property double nextResetAt: {
        if (!root.snapshot)
            return 0;
        const times = [root.snapshot.fiveHour?.resetAt, root.snapshot.weekly?.resetAt].filter(value => typeof value === "number" && value > root.snapshot.fetchedAt);
        return times.length > 0 ? Math.min(...times) : 0;
    }
    readonly property bool resetDue: root.nextResetAt > 0 && root.currentDate.getTime() >= root.nextResetAt

    onResetDueChanged: {
        if (root.resetDue)
            Qt.callLater(root.refreshAfterReset);
    }

    function refreshAfterReset() {
        if (!root.resetDue)
            return;
        root.available = false;
        root.error = "Reset due; refreshing quota";
        root.refresh(true);
    }

    function refresh(force) {
        const elapsed = Date.now() - root.lastAttemptAt;
        if (root.queryPending || queryProcess.running || !force && elapsed >= 0 && elapsed < 300000)
            return;
        root.lastAttemptAt = Date.now();
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
        const data = root.exitCode === 0 ? Usage.parseStatus(queryOutput.text) : null;
        if (!data) {
            root.available = false;
            root.error = root.exitCode === 0 ? "Invalid quota response" : queryError.text.trim().slice(0, 200) || "Quota query failed";
            return;
        }
        root.snapshot = data;
        root.error = "";
        root.available = true;
    }

    Process {
        id: queryProcess
        command: ["python3", Quickshell.shellPath("scripts/openai_usage.py")]
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
        interval: 15000
        repeat: false
        onTriggered: {
            root.queryPending = false;
            root.available = false;
            root.error = "Quota request timed out";
            queryProcess.running = false;
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }
}
