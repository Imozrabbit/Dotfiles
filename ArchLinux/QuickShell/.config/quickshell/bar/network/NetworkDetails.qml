import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property string interfaceName
    required property string connectionType

    property string ipAddressCidr: ""
    property int frequencyMhz: 0

    // Run these commands only when the tooltip requests details.
    function refreshDetails() {
        if (root.interfaceName === "")
            return;
        if (!addressProcess.running) {
            addressProcess.requestedInterface = root.interfaceName;
            addressProcess.running = true;
        }
        if (root.connectionType === "wifi" && !frequencyProcess.running) {
            frequencyProcess.requestedInterface = root.interfaceName;
            frequencyProcess.running = true;
        } else if (root.connectionType !== "wifi") {
            root.frequencyMhz = 0;
        }
    }

    Process {
        id: addressProcess
        property string requestedInterface: ""
        command: ["ip", "-j", "-4", "address", "show", "dev", requestedInterface]
        stdout: StdioCollector {
            id: addressOutput
            onStreamFinished: {
                // Ignore results from an interface that stopped being active while the command ran.
                if (addressProcess.requestedInterface !== root.interfaceName)
                    return;
                try {
                    const devices = JSON.parse(addressOutput.text);
                    const addresses = devices.length > 0 ? devices[0].addr_info : [];
                    const address = addresses.find(info => info.family === "inet" && info.scope === "global");
                    root.ipAddressCidr = address ? address.local + "/" + address.prefixlen : "";
                } catch (error) {
                    root.ipAddressCidr = "";
                }
            }
        }
    }

    Process {
        id: frequencyProcess
        property string requestedInterface: ""
        command: ["iw", "dev", frequencyProcess.requestedInterface, "link"]
        stdout: StdioCollector {
            id: frequencyOutput
            onStreamFinished: {
                // Ignore stale Wi-Fi results after an interface or connection-type change.
                if (frequencyProcess.requestedInterface !== root.interfaceName || root.connectionType !== "wifi")
                    return;
                const match = frequencyOutput.text.match(/^\s*freq:\s+(\d+)/m);
                const frequency = match ? Number(match[1]) : 0;
                root.frequencyMhz = isFinite(frequency) ? frequency : 0;
            }
        }
    }
}
