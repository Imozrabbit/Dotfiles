import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int memUsage: 0
    property real memTotalKib: -1
    property real memUsedKib: -1
    property real memAvailableKib: -1
    property real swapTotalKib: -1
    property real swapUsedKib: -1
    property bool memRowValid: false
    property bool swapRowValid: false

    Process {
        id: memProc
        command: ["env", "LC_ALL=C", "free"]
        onRunningChanged: {
            if (running) {
                root.memRowValid = false;
                root.swapRowValid = false;
                return;
            }

            if (!root.memRowValid) {
                root.memTotalKib = -1;
                root.memUsedKib = -1;
                root.memAvailableKib = -1;
            }
            if (!root.swapRowValid) {
                root.swapTotalKib = -1;
                root.swapUsedKib = -1;
            }
        }
        // SplitParser calls onRead for each line of output
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(/\s+/);
                // Expected line -> Mem: | total | used | free | shared | buff/cache | available
                if (parts[0] === "Mem:") {
                    if (parts.length < 7)
                        return;

                    const total = Number(parts[1]);
                    const used = Number(parts[2]);
                    const available = Number(parts[6]);
                    if (!isFinite(total) || total <= 0 || !isFinite(used) || used < 0 || used > total || !isFinite(available) || available < 0 || available > total)
                        return;

                    root.memTotalKib = total;
                    root.memUsedKib = used;
                    root.memAvailableKib = available;
                    root.memRowValid = true;
                    const nextUsage = Math.round(100 * (used / total));
                    root.memUsage = Math.max(0, Math.min(100, nextUsage));
                    return;
                }

                // Expected line -> Swap: | total | used | free
                if (parts[0] !== "Swap:" || parts.length < 4)
                    return;

                const total = Number(parts[1]);
                const used = Number(parts[2]);
                if (!isFinite(total) || total < 0 || !isFinite(used) || used < 0 || used > total)
                    return;

                root.swapTotalKib = total;
                root.swapUsedKib = used;
                root.swapRowValid = true;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!memProc.running)
                memProc.running = true;
        }
    }
}
