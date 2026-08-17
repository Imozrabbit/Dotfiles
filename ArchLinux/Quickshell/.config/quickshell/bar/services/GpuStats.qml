import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int gpuUsage: -1
    property int clockMhz: -1
    property int temperatureC: -1
    property string gpuName: "AMD Radeon Vega (Cezanne)"

    // Host-specific AMD paths. Find the card and its amdgpu hwmon directory with:
    // ls /sys/class/drm/card*/device/gpu_busy_percent
    // grep -l '^amdgpu$' /sys/class/drm/card*/device/hwmon/hwmon*/name
    readonly property string devicePath: "/sys/class/drm/card1/device"
    readonly property string hwmonPath: "/sys/class/drm/card1/device/hwmon/hwmon5"

    function readNumber(file) {
        const text = file.text().trim();
        return text === "" ? NaN : Number(text);
    }

    function refresh() {
        usageFile.reload();
        clockFile.reload();
        temperatureFile.reload();
    }

    FileView {
        id: usageFile

        path: root.devicePath + "/gpu_busy_percent"
        onLoaded: {
            const value = root.readNumber(usageFile);
            root.gpuUsage = isFinite(value) && value >= 0 && value <= 100 ? Math.round(value) : -1;
        }
        onLoadFailed: root.gpuUsage = -1
    }

    FileView {
        id: clockFile

        path: root.hwmonPath + "/freq1_input"
        onLoaded: {
            const value = root.readNumber(clockFile);
            root.clockMhz = isFinite(value) && value >= 0 ? Math.round(value / 1000000) : -1;
        }
        onLoadFailed: root.clockMhz = -1
    }

    FileView {
        id: temperatureFile

        path: root.hwmonPath + "/temp1_input"
        onLoaded: {
            const value = root.readNumber(temperatureFile);
            root.temperatureC = isFinite(value) && value >= 0 && value <= 200000 ? Math.round(value / 1000) : -1;
        }
        onLoadFailed: root.temperatureC = -1
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
