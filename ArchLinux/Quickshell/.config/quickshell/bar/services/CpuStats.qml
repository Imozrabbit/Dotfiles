import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int cpuUsage: 0
    property string cpuModel: "N/A"
    property int cpuClockMhz: -1
    property int cpuTemperatureC: -1
    property real lastCpuIdle: 0
    property real lastCpuTotal: 0

    function updateCpuInfo(data) {
        let model = "";
        let totalMhz = 0;
        let samples = 0;
        const lines = data.split("\n");

        for (let i = 0; i < lines.length; i++) {
            const separator = lines[i].indexOf(":");
            if (separator < 0)
                continue;

            const key = lines[i].slice(0, separator).trim();
            const text = lines[i].slice(separator + 1).trim();
            if (key === "model name" && model === "") {
                model = text;
            } else if (key === "cpu MHz" && text !== "") {
                const mhz = Number(text);
                if (isFinite(mhz) && mhz >= 0) {
                    totalMhz += mhz;
                    samples++;
                }
            }
        }

        root.cpuModel = model !== "" ? model : "N/A";
        root.cpuClockMhz = samples > 0 ? Math.round(totalMhz / samples) : -1;
    }

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

    FileView {
        id: cpuInfoFile

        path: "/proc/cpuinfo"
        onLoaded: root.updateCpuInfo(cpuInfoFile.text())
        onLoadFailed: {
            root.cpuModel = "N/A";
            root.cpuClockMhz = -1;
        }
    }

    FileView {
        id: temperatureFile

        // Host-specific. Find the k10temp hwmon directory with:
        // grep -l '^k10temp$' /sys/class/hwmon/hwmon*/name
        path: "/sys/class/hwmon/hwmon6/temp1_input"
        onLoaded: {
            const text = temperatureFile.text().trim();
            const value = text === "" ? NaN : Number(text);
            root.cpuTemperatureC = isFinite(value) && value >= 0 && value <= 200000 ? Math.round(value / 1000) : -1;
        }
        onLoadFailed: root.cpuTemperatureC = -1
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cpuProc.running)
                cpuProc.running = true;
            cpuInfoFile.reload();
            temperatureFile.reload();
        }
    }
}
