// Mem.qml
pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Read 0 to 1
    property real used01: 0.0

    Process {
        id: memProc
        command: ["sh", "-c", "awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {if (t>0) printf \"%.6f\\n\", (t-a)/t; else print \"0\"}' /proc/meminfo"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const v = Number(this.text.trim());
                if (isFinite(v))
                    root.used01 = Math.max(0, Math.min(1, v));
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: memProc.running = true
    }
}
