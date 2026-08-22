import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property string vpnName: ""
    property bool statusKnown: false
    readonly property bool ifVpn: root.vpnName !== ""
    readonly property string dnsName: root.statusKnown ? (root.ifVpn ? "Proton" : "NextDNS") : ""
    readonly property bool checkingVpn: updateVpnProcess.running

    function refreshVpn() {
        if (updateVpnProcess.running)
            return;
        updateVpnProcess.running = true;
    }

    function applyVpnStatus(output) {
        const lines = String(output || "").split(/\r?\n/);
        let activeVpn = "";

        for (let line of lines) {
            if (line.trim() === "")
                continue;

            const separator = line.lastIndexOf(":");
            const name = line.slice(0, separator).trim();
            const type = line.slice(separator + 1).trim();
            if (separator < 1 || name === "" || type === "") {
                root.vpnName = "";
                root.statusKnown = false;
                return;
            }
            if (activeVpn === "" && (type === "wireguard" || type === "vpn"))
                activeVpn = name;
        }

        root.vpnName = activeVpn;
        root.statusKnown = true;
    }

    Process {
        id: updateVpnProcess
        command: ["nmcli", "--wait", "2", "--terse", "--escape", "no", "--fields", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            id: vpnOutput
        }
        onExited: function (exitCode) {
            if (exitCode === 0) {
                root.applyVpnStatus(vpnOutput.text);
            } else {
                root.vpnName = "";
                root.statusKnown = false;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshVpn()
    }
}
