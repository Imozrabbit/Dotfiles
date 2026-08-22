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
    property real energyFullDesignUwh: -1
    property real powerNowUw: -1
    property int chargeStartThreshold: -1
    property int chargeEndThreshold: -1
    property int cycleCount: -1
    property string activePowerProfile: ""
    property string actionError: ""
    property string pendingAction: ""
    property bool profileRefreshPending: false
    property bool thresholdRefreshPending: false
    property int pendingChargeStartThreshold: -1
    property int pendingChargeEndThreshold: -1
    property int chargeLimitGeneration: 0
    property bool chargeReadbackPending: false
    readonly property bool actionBusy: actionProcess.running || root.chargeReadbackPending

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
        const value = /^\d+$/.test(text) ? Number(text) : -1;
        return Number.isSafeInteger(value) ? value : -1;
    }

    function validThresholdPair(start, end) {
        return Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && start <= 100 && end >= 0 && end <= 100 && end > start;
    }

    function refreshThresholds() {
        if (actionProcess.running || thresholdQueryProcess.running) {
            root.thresholdRefreshPending = true;
            return;
        }
        root.thresholdRefreshPending = false;
        thresholdQueryProcess.requestGeneration = root.chargeLimitGeneration;
        thresholdQueryProcess.running = true;
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
        energyFullDesignFile.reload();
        powerNowFile.reload();
        root.refreshThresholds();
        cycleCountFile.reload();
    }

    function refreshPowerProfile() {
        if (profileQueryProcess.running) {
            root.profileRefreshPending = true;
            return;
        }
        root.profileRefreshPending = false;
        profileQueryProcess.running = true;
    }

    function setPowerProfile(profile) {
        if (root.actionBusy || (profile !== "power-saver" && profile !== "balanced" && profile !== "performance"))
            return;

        root.actionError = "";
        root.pendingAction = "profile";
        actionProcess.command = ["powerprofilesctl", "set", profile];
        actionProcess.running = true;
    }

    function setChargeThresholds(startValue, endValue) {
        const start = Number(startValue);
        const end = Number(endValue);
        const invalid = !isFinite(start) || !isFinite(end) || start !== Math.round(start) || end !== Math.round(end) || start % 5 !== 0 || end % 5 !== 0 || start < 45 || start > 95 || end < 50 || end > 100 || end <= start;
        if (root.actionBusy || root.chargeStartThreshold < 0 || root.chargeEndThreshold < 0 || invalid) {
            root.actionError = "Invalid charge limit";
            return;
        }

        root.actionError = "";
        root.pendingAction = "charge-limit";
        root.pendingChargeStartThreshold = start;
        root.pendingChargeEndThreshold = end;
        root.chargeLimitGeneration++;
        actionProcess.command = ["sudo", "-n", "sh", "-c", `
            new_start="$1"
            new_end="$2"
            start_path="$3"
            end_path="$4"

            valid_threshold() {
                case "$1" in
                    [0-9]|[0-9][0-9]|100) return 0 ;;
                    *) return 1 ;;
                esac
            }

            status=0
            old_start="$(cat "$start_path" 2>/dev/null)" || status=2
            old_end="$(cat "$end_path" 2>/dev/null)" || status=2
            if ! valid_threshold "$old_start" || ! valid_threshold "$old_end"; then
                status=2
            elif [ "$old_end" -le "$old_start" ]; then
                status=2
            fi

            if [ "$status" -eq 0 ] && [ "$new_start" -ge "$old_end" ]; then
                if ! printf '%s' "$new_end" > "$end_path"; then
                    status=1
                elif ! printf '%s' "$new_start" > "$start_path"; then
                    if ! printf '%s' "$old_end" > "$end_path"; then
                        status=2
                    else
                        status=1
                    fi
                fi
            elif [ "$status" -eq 0 ]; then
                if ! printf '%s' "$new_start" > "$start_path"; then
                    status=1
                elif ! printf '%s' "$new_end" > "$end_path"; then
                    if ! printf '%s' "$old_start" > "$start_path"; then
                        status=2
                    else
                        status=1
                    fi
                fi
            fi

            actual_start="$(cat "$start_path" 2>/dev/null)" || status=2
            actual_end="$(cat "$end_path" 2>/dev/null)" || status=2
            printf '__LIMITS:%s:%s\n' "$actual_start" "$actual_end"
            exit "$status"
        `, "sh", start.toString(), end.toString(), root.batteryPath + "/charge_control_start_threshold", root.batteryPath + "/charge_control_end_threshold"];
        actionProcess.running = true;
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
            root.statusValid = value === "Unknown" || value === "Charging" || value === "Discharging" || value === "Not charging" || value === "Full";
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
        id: energyFullDesignFile

        path: root.batteryPath + "/energy_full_design"
        onLoaded: root.energyFullDesignUwh = root.readUnsignedInteger(energyFullDesignFile)
        onLoadFailed: root.energyFullDesignUwh = -1
    }

    FileView {
        id: powerNowFile

        path: root.batteryPath + "/power_now"
        onLoaded: root.powerNowUw = root.readUnsignedInteger(powerNowFile)
        onLoadFailed: root.powerNowUw = -1
    }

    FileView {
        id: cycleCountFile

        path: root.batteryPath + "/cycle_count"
        onLoaded: {
            const value = root.readUnsignedInteger(cycleCountFile);
            root.cycleCount = value >= 0 ? value : -1;
        }
        onLoadFailed: root.cycleCount = -1
    }

    Process {
        id: thresholdQueryProcess
        property int requestGeneration: -1

        command: ["cat", root.batteryPath + "/charge_control_start_threshold", root.batteryPath + "/charge_control_end_threshold"]
        stdout: StdioCollector {
            id: thresholdQueryOutput
        }
        onExited: function (exitCode) {
            if (requestGeneration === root.chargeLimitGeneration) {
                const fields = thresholdQueryOutput.text.trim().split(/\s+/);
                const validFormat = fields.length === 2 && fields.every(value => /^\d+$/.test(value));
                const values = validFormat ? fields.map(Number) : [-1, -1];
                const valid = exitCode === 0 && root.validThresholdPair(values[0], values[1]);
                root.chargeStartThreshold = valid ? values[0] : -1;
                root.chargeEndThreshold = valid ? values[1] : -1;
                root.chargeReadbackPending = false;
            }
            if (root.thresholdRefreshPending)
                Qt.callLater(root.refreshThresholds);
        }
    }

    Process {
        id: profileQueryProcess

        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            id: profileQueryOutput
        }
        onExited: function (exitCode) {
            const refreshAgain = root.profileRefreshPending;
            root.profileRefreshPending = false;
            if (exitCode !== 0) {
                root.activePowerProfile = "";
            } else {
                const profile = profileQueryOutput.text.trim();
                root.activePowerProfile = profile === "power-saver" || profile === "balanced" || profile === "performance" ? profile : "";
            }

            if (refreshAgain)
                Qt.callLater(root.refreshPowerProfile);
        }
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {
            id: actionOutput
        }
        onExited: function (exitCode) {
            const action = root.pendingAction;
            root.pendingAction = "";
            if (action === "charge-limit") {
                const match = actionOutput.text.match(/__LIMITS:(\d+):(\d+)/);
                const confirmedStart = match ? Number(match[1]) : -1;
                const confirmedEnd = match ? Number(match[2]) : -1;
                const confirmed = root.validThresholdPair(confirmedStart, confirmedEnd);
                if (confirmed) {
                    root.chargeStartThreshold = confirmedStart;
                    root.chargeEndThreshold = confirmedEnd;
                }
                root.actionError = exitCode === 0 && confirmedStart === root.pendingChargeStartThreshold && confirmedEnd === root.pendingChargeEndThreshold ? "" : "Could not change charge limits";
                root.pendingChargeStartThreshold = -1;
                root.pendingChargeEndThreshold = -1;
                if (!confirmed) {
                    root.chargeStartThreshold = -1;
                    root.chargeEndThreshold = -1;
                    root.chargeReadbackPending = true;
                    Qt.callLater(root.refreshThresholds);
                }
                return;
            }

            if (exitCode !== 0) {
                root.actionError = "Could not change power profile";
            } else if (action === "profile") {
                root.actionError = "";
                root.refreshPowerProfile();
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

    Component.onCompleted: root.refreshPowerProfile()
}
