import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool available: false
    property int capacity: -1
    property string status: "Unknown"
    property bool acOnline: false
    property real energyNowUwh: -1
    property real energyFullUwh: -1
    property real powerNowUw: -1
    property int chargeStartThreshold: -1
    property int chargeEndThreshold: -1

    property bool batteryPresent: false
    property bool capacityValid: false
    property bool statusValid: false
    property bool presentValid: false

    // Host-specific names. Find battery and mains devices under:
    // /sys/class/power_supply
    readonly property string batteryPath: "/sys/class/power_supply/BAT0"
    readonly property string acPath: "/sys/class/power_supply/AC"

    function readUnsignedInteger(file) {
        const text = file.text().trim();
        return /^\d+$/.test(text) ? Number(text) : -1;
    }

    function updateAvailability() {
        root.available = root.capacityValid && root.statusValid && root.presentValid && root.batteryPresent;
    }

    function refresh() {
        capacityFile.reload();
        statusFile.reload();
        presentFile.reload();
        acFile.reload();
        energyNowFile.reload();
        energyFullFile.reload();
        powerNowFile.reload();
        chargeStartFile.reload();
        chargeEndFile.reload();
    }

    FileView {
        id: capacityFile

        path: root.batteryPath + "/capacity"
        onLoaded: {
            const value = root.readUnsignedInteger(capacityFile);
            root.capacityValid = value >= 0 && value <= 100;
            root.capacity = root.capacityValid ? value : -1;
            root.updateAvailability();
        }
        onLoadFailed: {
            root.capacityValid = false;
            root.capacity = -1;
            root.updateAvailability();
        }
    }

    FileView {
        id: statusFile

        path: root.batteryPath + "/status"
        onLoaded: {
            const value = statusFile.text().trim();
            root.statusValid = value !== "";
            root.status = root.statusValid ? value : "Unknown";
            root.updateAvailability();
        }
        onLoadFailed: {
            root.statusValid = false;
            root.status = "Unknown";
            root.updateAvailability();
        }
    }

    FileView {
        id: presentFile

        path: root.batteryPath + "/present"
        onLoaded: {
            const value = root.readUnsignedInteger(presentFile);
            root.presentValid = value === 0 || value === 1;
            root.batteryPresent = root.presentValid && value === 1;
            root.updateAvailability();
        }
        onLoadFailed: {
            root.presentValid = false;
            root.batteryPresent = false;
            root.updateAvailability();
        }
    }

    FileView {
        id: acFile

        path: root.acPath + "/online"
        onLoaded: {
            const value = root.readUnsignedInteger(acFile);
            root.acOnline = value === 1;
        }
        onLoadFailed: root.acOnline = false
    }

    FileView {
        id: energyNowFile

        path: root.batteryPath + "/energy_now"
        onLoaded: root.energyNowUwh = root.readUnsignedInteger(energyNowFile)
        onLoadFailed: root.energyNowUwh = -1
    }

    FileView {
        id: energyFullFile

        path: root.batteryPath + "/energy_full"
        onLoaded: root.energyFullUwh = root.readUnsignedInteger(energyFullFile)
        onLoadFailed: root.energyFullUwh = -1
    }

    FileView {
        id: powerNowFile

        path: root.batteryPath + "/power_now"
        onLoaded: root.powerNowUw = root.readUnsignedInteger(powerNowFile)
        onLoadFailed: root.powerNowUw = -1
    }

    FileView {
        id: chargeStartFile

        path: root.batteryPath + "/charge_control_start_threshold"
        onLoaded: {
            const value = root.readUnsignedInteger(chargeStartFile);
            root.chargeStartThreshold = value <= 100 ? value : -1;
        }
        onLoadFailed: root.chargeStartThreshold = -1
    }

    FileView {
        id: chargeEndFile

        path: root.batteryPath + "/charge_control_end_threshold"
        onLoaded: {
            const value = root.readUnsignedInteger(chargeEndFile);
            root.chargeEndThreshold = value <= 100 ? value : -1;
        }
        onLoadFailed: root.chargeEndThreshold = -1
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
