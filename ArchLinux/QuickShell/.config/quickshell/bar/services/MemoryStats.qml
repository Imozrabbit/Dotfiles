import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int memUsage: 0

    Process {
        id: memProc
        command: ["free"]
        // SplitParser calls onRead for each line of output
        stdout: SplitParser {
            onRead: data => {
                // Expected line -> Mem: | total | used | free | shared | buff/cache | available
                var parts = data.trim().split(/\s+/);
                if (parts.length < 3 || parts[0] !== "Mem:")
                    return;

                var total = Number(parts[1]);
                var used = Number(parts[2]);
                if (!isFinite(total) || total <= 0 || !isFinite(used) || used < 0 || used > total)
                    return;

                const nextUsage = Math.round(100 * (used / total));
                root.memUsage = Math.max(0, Math.min(100, nextUsage));
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
