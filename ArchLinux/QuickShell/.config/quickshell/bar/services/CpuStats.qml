import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int cpuUsage: 0
    property real lastCpuIdle: 0
    property real lastCpuTotal: 0

    Process {
        id: cpuProc
        command: ["head", "-n", "1", "/proc/stat"]
        // SplitParser calls onRead for each line of output
        stdout: SplitParser {
            onRead: data => {
                // Use aggregate CPU fields through steal
                // Guest fields are excluded because they are already included in user and nice
                // p[0]
                // p[1]: user
                // p[2]: nice
                // p[3]: system
                // p[4]: idle
                // p[5]: iowait
                // p[6]: irq
                // p[7]: softirq
                // p[8]: steal

                // Split the data into an array of multiple elements, and verify it is indeed the cpu data
                var p = data.trim().split(/\s+/);
                if (p.length < 9 || p[0] !== "cpu")
                    return;

                var idle = parseInt(p[4]) + parseInt(p[5]);                     // adds idle and iowait => idle
                var total = p.slice(1, 9).reduce((a, b) => a + parseInt(b), 0); // Adds every element from 1 to 8 together => total
                if (!isFinite(idle) || !isFinite(total))
                    return;

                var totalDelta = total - root.lastCpuTotal; // Calculate the total difference
                var idleDelta = idle - root.lastCpuIdle;    // Calcualte the idle difference

                // Make sure there is no division by 0 and lastCpuTotal exists
                if (root.lastCpuTotal > 0 && totalDelta > 0 && idleDelta >= 0 && idleDelta <= totalDelta) {
                    const nextUsage = Math.round(100 * (1 - idleDelta / totalDelta));
                    root.cpuUsage = Math.max(0, Math.min(100, nextUsage));
                }
                root.lastCpuTotal = total;
                root.lastCpuIdle = idle;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cpuProc.running)
                cpuProc.running = true;
        }
    }
}
