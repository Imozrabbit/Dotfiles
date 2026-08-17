import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool available: false
    property real brightness: 0.01
    property int keyboardBacklight: 0

    function refresh() {
        if (!queryProcess.running)
            queryProcess.running = true;
    }

    function setBrightness(value) {
        if (!root.available || setProcess.running)
            return;

        const percent = Math.round(Math.max(0.01, Math.min(1.0, value)) * 100);
        setProcess.command = ["brightnessctl", "set", percent + "%"];
        setProcess.running = true;
    }

    function cycleKeyboardBacklight() {
        if (!getKeyboardBrightness.running && !setKeyboardBrightness.running)
            getKeyboardBrightness.running = true;
    }

    Process {
        id: getKeyboardBrightness
        command: ["brightnessctl", "-d", "tpacpi::kbd_backlight", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const current = Number(text.trim());
                const next = (current + 1) % 3;
                root.keyboardBacklight = next;
                setKeyboardBrightness.command = ["brightnessctl", "-q", "-d", "tpacpi::kbd_backlight", "set", next.toString()];
                setKeyboardBrightness.running = true;
            }
        }
    }

    Process {
        id: setKeyboardBrightness
    }

    Process {
        id: queryProcess

        command: ["brightnessctl", "--machine-readable", "info"]
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
            }
        }
    }

    Process {
        id: setProcess

        onRunningChanged: {
            if (!running)
                root.refresh();
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
