import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool available: false
    property real brightness: 0.01
    property string keyboardDevice: ""
    property int keyboardMaximum: -1
    property bool queryValid: false
    property bool pendingBrightness: false
    property real requestedBrightness: 0.01

    function refresh() {
        if (!queryProcess.running)
            queryProcess.running = true;
    }

    function setBrightness(value) {
        if (!root.available || !isFinite(value))
            return;

        root.requestedBrightness = Math.max(0.01, Math.min(1.0, value));
        root.pendingBrightness = true;
        root.applyBrightness();
    }

    function applyBrightness() {
        if (!root.pendingBrightness || setProcess.running)
            return;
        root.pendingBrightness = false;
        const percent = Math.round(root.requestedBrightness * 100);
        setProcess.command = ["brightnessctl", "set", percent + "%"];
        setProcess.running = true;
    }

    function cycleKeyboardBacklight() {
        if (root.keyboardDevice === "" || root.keyboardMaximum < 1)
            return;
        if (!getKeyboardBrightness.running && !setKeyboardBrightness.running)
            getKeyboardBrightness.running = true;
    }

    Process {
        id: keyboardDiscovery

        command: ["sh", "-c", `
            for device in /sys/class/leds/*::kbd_backlight; do
                [ -r "$device/max_brightness" ] || continue
                read -r maximum < "$device/max_brightness"
                case "$maximum" in
                    ""|0|*[!0-9]*) continue ;;
                esac
                printf '%s|%s\\n' "$(basename "$device")" "$maximum"
                exit 0
            done
            exit 1
        `]
        stdout: StdioCollector {
            id: keyboardDiscoveryOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            const fields = keyboardDiscoveryOutput.text.trim().split("|");
            if (exitCode !== 0 || fields.length !== 2 || !/^[A-Za-z0-9_.:-]+::kbd_backlight$/.test(fields[0]) || !/^\d+$/.test(fields[1]))
                return;
            const maximum = Number(fields[1]);
            if (!Number.isSafeInteger(maximum) || maximum < 1 || maximum > 1000)
                return;
            root.keyboardDevice = fields[0];
            root.keyboardMaximum = maximum;
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: getKeyboardBrightness
        command: ["brightnessctl", "-d", root.keyboardDevice, "get"]
        stdout: StdioCollector {
            id: keyboardOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            const text = keyboardOutput.text.trim();
            if (exitCode !== 0 || !/^\d+$/.test(text))
                return;
            const current = Number(text);
            if (!Number.isSafeInteger(current) || current < 0 || current > root.keyboardMaximum)
                return;
            const next = (current + 1) % (root.keyboardMaximum + 1);
            setKeyboardBrightness.command = ["brightnessctl", "-q", "-d", root.keyboardDevice, "set", next.toString()];
            setKeyboardBrightness.running = true;
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: setKeyboardBrightness
    }

    Process {
        id: queryProcess

        command: ["brightnessctl", "--machine-readable", "info"]
        onRunningChanged: {
            if (running)
                root.queryValid = false;
            else if (!root.queryValid)
                root.available = false;
        }
        stdout: SplitParser {
            onRead: data => {
                const fields = data.trim().split(",");
                if (fields.length < 5)
                    return;

                const current = Number(fields[2]);
                const maximum = Number(fields[4]);
                if (!isFinite(current) || current < 0 || !isFinite(maximum) || maximum <= 0 || current > maximum)
                    return;

                root.brightness = Math.max(0.01, Math.min(1.0, current / maximum));
                root.available = true;
                root.queryValid = true;
            }
        }
    }

    Process {
        id: setProcess

        onRunningChanged: {
            if (!running) {
                root.refresh();
                root.applyBrightness();
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: keyboardDiscovery.running = true
}
