import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool available: false
    property bool powered: false
    property bool connected: false
    property bool detailsKnown: false
    property var devices: []
    property string actionAddress: ""
    property string actionError: ""
    property string pendingActionError: ""

    readonly property var connectedDevices: root.devices.filter(device => device.connected)
    readonly property var disconnectedDevices: root.devices.filter(device => !device.connected)
    readonly property bool actionBusy: actionProcess.running

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function applyStatus(output) {
        const sections = String(output || "").split("__CONNECTED__");
        const adapter = sections[0] || "";
        const devices = sections[1] || "";

        root.available = adapter.indexOf("Controller ") !== -1;
        root.powered = root.available && /^\s*Powered:\s+yes\s*$/m.test(adapter);
        root.connected = root.powered && /^Device\s+/m.test(devices.trim());
    }

    function refreshDetails() {
        if (!detailsProcess.running)
            detailsProcess.running = true;
    }

    function applyDetails(output) {
        const devices = [];
        const lines = String(output || "").split(/\r?\n/);
        let device = null;

        for (let line of lines) {
            if (line.indexOf("__DEVICE__\t") === 0) {
                if (device)
                    devices.push(device);
                const fields = line.split("\t");
                device = {
                    address: fields[1] || "",
                    name: fields.slice(2).join("\t") || fields[1] || "Unknown device",
                    icon: "",
                    connected: false,
                    battery: -1
                };
                continue;
            }
            if (!device)
                continue;

            const value = line.trim();
            let match = value.match(/^Alias:\s*(.+)$/);
            if (match) {
                device.name = match[1].trim();
                continue;
            }
            match = value.match(/^Icon:\s*(.+)$/);
            if (match) {
                device.icon = match[1].trim();
                continue;
            }
            match = value.match(/^Connected:\s*(yes|no)$/);
            if (match) {
                device.connected = match[1] === "yes";
                continue;
            }
            match = value.match(/^Battery Percentage:\s*\S+\s*\((\d+)\)$/);
            if (match)
                device.battery = Math.max(0, Math.min(100, Number(match[1])));
        }
        if (device)
            devices.push(device);

        root.devices = devices.filter(entry => /^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$/i.test(entry.address));
        root.connected = root.powered && root.devices.some(entry => entry.connected);
        root.detailsKnown = true;
    }

    function validAddress(address) {
        return /^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$/i.test(String(address || ""));
    }

    function runAction(command, address, errorMessage) {
        if (actionProcess.running || (address !== "" && !root.validAddress(address)))
            return;
        root.actionAddress = address;
        root.actionError = "";
        root.pendingActionError = errorMessage;
        actionProcess.command = command;
        actionProcess.running = true;
    }

    function setPowered(enabled) {
        root.runAction(["bluetoothctl", "power", enabled ? "on" : "off"], "", "Could not change Bluetooth power");
    }

    function connectDevice(address) {
        root.runAction(["bluetoothctl", "connect", address], address, "Could not connect device");
    }

    function disconnectDevice(address) {
        root.runAction(["bluetoothctl", "disconnect", address], address, "Could not disconnect device");
    }

    function openManager() {
        Quickshell.execDetached(["ghostty", "--class=bluetui", "--title=Bluetooth", "-e", "bluetui"]);
    }

    Process {
        id: statusProcess

        command: ["sh", "-c", "bluetoothctl show 2>/dev/null; printf '__CONNECTED__\\n'; bluetoothctl devices Connected 2>/dev/null"]
        stdout: StdioCollector {
            id: statusOutput
        }
        onExited: root.applyStatus(statusOutput.text)
    }

    Process {
        id: detailsProcess

        command: ["sh", "-c", "bluetoothctl devices Paired 2>/dev/null | while read -r _ address name; do printf '__DEVICE__\\t%s\\t%s\\n' \"$address\" \"$name\"; bluetoothctl info \"$address\" 2>/dev/null; done"]
        stdout: StdioCollector {
            id: detailsOutput
        }
        onExited: root.applyDetails(detailsOutput.text)
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {
            id: actionOutput
        }
        onExited: function (exitCode) {
            root.actionError = exitCode === 0 ? "" : root.pendingActionError;
            root.actionAddress = "";
            root.pendingActionError = "";
            Qt.callLater(root.refresh);
            Qt.callLater(root.refreshDetails);
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
