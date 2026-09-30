import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int gpuUsage: -1
    property int clockMhz: -1
    property int temperatureC: -1
    property string gpuName: "GPU unavailable"
    property string devicePath: ""
    property string hwmonPath: ""

    function readNumber(file) {
        const text = file.text().trim();
        return text === "" ? NaN : Number(text);
    }

    function refresh() {
        if (root.devicePath !== "")
            usageFile.reload();
        if (root.hwmonPath !== "") {
            clockFile.reload();
            temperatureFile.reload();
        }
    }

    Process {
        id: gpuDiscovery

        command: ["sh", "-c", `
            amd_device=""
            unsupported=""
            for device in /sys/class/drm/card[0-9]*/device; do
                [ -r "$device/vendor" ] || continue
                read -r vendor < "$device/vendor"
                case "$vendor" in
                    0x1002)
                        [ -r "$device/gpu_busy_percent" ] || continue
                        [ -n "$amd_device" ] || amd_device="$device"
                        for name in "$device"/hwmon/hwmon*/name; do
                            [ -r "$name" ] || continue
                            read -r driver < "$name"
                            if [ "$driver" = amdgpu ]; then
                                printf 'AMD|%s|%s\\n' "$device" "$(dirname "$name")"
                                exit 0
                            fi
                        done
                        ;;
                    0x8086) [ -n "$unsupported" ] || unsupported=Intel ;;
                    0x10de) [ -n "$unsupported" ] || unsupported=NVIDIA ;;
                esac
            done
            if [ -n "$amd_device" ]; then
                printf 'AMD|%s|\\n' "$amd_device"
            else
                printf '%s||\\n' "$unsupported"
            fi
        `]
        stdout: StdioCollector {
            id: gpuDiscoveryOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            const fields = gpuDiscoveryOutput.text.trim().split("|");
            if (exitCode !== 0 || fields.length !== 3)
                return;
            if (fields[0] === "AMD" && /^\/sys\/class\/drm\/card\d+\/device$/.test(fields[1])) {
                root.devicePath = fields[1];
                if (/^\/sys\/class\/drm\/card\d+\/device\/hwmon\/hwmon\d+$/.test(fields[2]) && fields[2].startsWith(fields[1] + "/hwmon/"))
                    root.hwmonPath = fields[2];
                root.gpuName = "AMD GPU";
                root.refresh();
                gpuNameProcess.running = true;
            } else if ((fields[0] === "Intel" || fields[0] === "NVIDIA") && fields[1] === "" && fields[2] === "") {
                root.gpuName = fields[0] + " GPU metrics not implemented";
            }
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: gpuNameProcess

        command: ["sh", "-c", "pci=$(basename \"$(readlink -f \"$1\")\") && lspci -s \"$pci\" -vmm 2>/dev/null", "sh", root.devicePath]
        stdout: StdioCollector {
            id: gpuNameOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            const match = gpuNameOutput.text.match(/^Device:[ \t]*([^\r\n]+)$/m);
            const name = match ? match[1].trim() : "";
            if (exitCode === 0 && name !== "" && name.length <= 120)
                root.gpuName = name.startsWith("AMD ") ? name : "AMD " + name;
        }
        // qmllint enable signal-handler-parameters
    }

    FileView {
        id: usageFile

        path: root.devicePath === "" ? "" : root.devicePath + "/gpu_busy_percent"
        onLoaded: {
            const value = root.readNumber(usageFile);
            root.gpuUsage = isFinite(value) && value >= 0 && value <= 100 ? Math.round(value) : -1;
        }
        onLoadFailed: root.gpuUsage = -1
    }

    FileView {
        id: clockFile

        path: root.hwmonPath === "" ? "" : root.hwmonPath + "/freq1_input"
        onLoaded: {
            const value = root.readNumber(clockFile);
            root.clockMhz = isFinite(value) && value >= 0 ? Math.round(value / 1000000) : -1;
        }
        onLoadFailed: root.clockMhz = -1
    }

    FileView {
        id: temperatureFile

        path: root.hwmonPath === "" ? "" : root.hwmonPath + "/temp1_input"
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

    Component.onCompleted: gpuDiscovery.running = true
}
