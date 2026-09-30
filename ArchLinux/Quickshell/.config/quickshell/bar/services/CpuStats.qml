import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int cpuUsage: 0
    property string cpuModel: "N/A"
    property int cpuClockMhz: -1
    property int cpuTemperatureC: -1
    property string temperaturePath: ""
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

    function resetCpuSample() {
        root.cpuUsage = -1;
        root.lastCpuIdle = 0;
        root.lastCpuTotal = 0;
    }

    function updateCpuSample(data) {
        const fields = data.split("\n", 1)[0].trim().split(/\s+/);
        const values = fields.slice(1, 9).map(Number);
        if (fields[0] !== "cpu" || values.length !== 8 || !values.every(value => Number.isSafeInteger(value) && value >= 0)) {
            root.resetCpuSample();
            return;
        }

        const idle = values[3] + values[4];
        const total = values.reduce((sum, value) => sum + value, 0);
        const totalDelta = total - root.lastCpuTotal;
        const idleDelta = idle - root.lastCpuIdle;
        if (root.lastCpuTotal > 0 && totalDelta > 0 && idleDelta >= 0 && idleDelta <= totalDelta)
            root.cpuUsage = Math.max(0, Math.min(100, Math.round(100 * (1 - idleDelta / totalDelta))));
        root.lastCpuTotal = total;
        root.lastCpuIdle = idle;
    }

    FileView {
        id: cpuStatFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: root.updateCpuSample(text())
        onLoadFailed: root.resetCpuSample()
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

        path: root.temperaturePath
        onLoaded: {
            const text = temperatureFile.text().trim();
            const value = text === "" ? NaN : Number(text);
            root.cpuTemperatureC = isFinite(value) && value >= 0 && value <= 200000 ? Math.round(value / 1000) : -1;
        }
        onLoadFailed: root.cpuTemperatureC = -1
    }

    Process {
        id: temperatureSensorProcess

        command: ["sh", "-c", `
            for name in /sys/class/hwmon/hwmon*/name; do
                [ -r "$name" ] || continue
                read -r driver < "$name"
                case "$driver" in
                    k10temp|coretemp)
                        printf '%s/temp1_input\\n' "$(dirname "$name")"
                        exit 0
                        ;;
                esac
            done
            exit 1
        `]
        stdout: StdioCollector {
            id: temperatureSensorOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            const path = temperatureSensorOutput.text.trim();
            const validPath = /^\/sys\/class\/hwmon\/hwmon\d+\/temp1_input$/.test(path);
            root.temperaturePath = exitCode === 0 && validPath ? path : "";
            if (root.temperaturePath !== "")
                temperatureFile.reload();
        }
        // qmllint enable signal-handler-parameters
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuStatFile.reload();
            cpuInfoFile.reload();
            if (root.temperaturePath !== "")
                temperatureFile.reload();
        }
    }

    Component.onCompleted: temperatureSensorProcess.running = true
}
