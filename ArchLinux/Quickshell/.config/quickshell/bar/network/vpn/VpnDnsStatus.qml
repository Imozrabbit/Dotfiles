import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string homeNetworkName: "HouseOfAnton_5GHz"
    readonly property var nextDnsAddresses: ["45.90.28.0", "45.90.30.0", "2a07:a8c0::", "2a07:a8c1::"]

    property string networkName: ""
    property bool queriesEnabled: true

    property string awayVpnName: ""
    property bool vpnKnown: false
    property string awayDnsName: ""
    property string awayDnsServers: ""
    property bool awayDnsKnown: false

    readonly property bool atHome: root.networkName === root.homeNetworkName
    readonly property string protectionMode: root.atHome ? "home" : !root.vpnKnown ? "unknown" : root.awayVpnName !== "" ? "vpn" : "unprotected"
    readonly property string vpnName: root.atHome ? "Router-managed" : root.awayVpnName
    readonly property string dnsName: root.atHome ? "Router-managed" : root.awayDnsName
    readonly property string dnsServers: root.atHome ? "" : root.awayDnsServers
    readonly property bool dnsKnown: root.atHome || root.awayDnsKnown
    readonly property bool dnsExpected: root.atHome || (root.protectionMode === "vpn" && root.awayDnsKnown && root.awayDnsName === "NextDNS")

    function clearAwayState() {
        root.awayVpnName = "";
        root.vpnKnown = false;
        root.awayDnsName = "";
        root.awayDnsServers = "";
        root.awayDnsKnown = false;
    }

    function clearDns() {
        root.awayDnsName = "Unavailable";
        root.awayDnsServers = "";
        root.awayDnsKnown = false;
    }

    function applyVpnStatus(output) {
        if (root.atHome)
            return;

        let activeVpn = "";
        for (let line of String(output || "").split(/\r?\n/)) {
            if (line.trim() === "")
                continue;

            const separator = line.lastIndexOf(":");
            if (separator < 1) {
                root.awayVpnName = "";
                root.vpnKnown = false;
                return;
            }

            const name = line.slice(0, separator).trim();
            const type = line.slice(separator + 1).trim();
            if (activeVpn === "" && (type === "wireguard" || type === "vpn"))
                activeVpn = name;
        }

        root.awayVpnName = activeVpn;
        root.vpnKnown = true;
    }

    function applyDnsStatus(output) {
        if (root.atHome)
            return;

        const entries = [];
        for (let line of String(output || "").split(/\r?\n/)) {
            const separator = line.indexOf(":");
            if (separator < 0)
                continue;
            for (let address of line.slice(separator + 1).trim().split(/\s+/)) {
                if (address !== "" && !entries.includes(address))
                    entries.push(address);
            }
        }

        if (entries.length === 0) {
            root.clearDns();
            return;
        }

        root.awayDnsName = entries.some(address => root.nextDnsAddresses.includes(address.split("#")[0])) ? "NextDNS" : "Other";
        root.awayDnsServers = entries.slice(0, 2).join(", ");
        root.awayDnsKnown = true;
    }

    function refresh() {
        if (!root.queriesEnabled || root.atHome)
            return;
        if (!updateVpnProcess.running)
            updateVpnProcess.running = true;
        if (!updateDnsProcess.running)
            updateDnsProcess.running = true;
    }

    onNetworkNameChanged: {
        root.clearAwayState();
        if (!root.atHome)
            Qt.callLater(root.refresh);
    }

    Process {
        id: updateVpnProcess
        command: ["nmcli", "--wait", "2", "--terse", "--escape", "no", "--fields", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            id: vpnOutput
        }
        onExited: function (exitCode) {
            if (root.atHome)
                return;
            if (exitCode === 0)
                root.applyVpnStatus(vpnOutput.text);
            else {
                root.awayVpnName = "";
                root.vpnKnown = false;
            }
        }
    }

    Process {
        id: updateDnsProcess
        command: ["resolvectl", "dns"]
        stdout: StdioCollector {
            id: dnsOutput
        }
        onExited: function (exitCode) {
            if (root.atHome)
                return;
            if (exitCode === 0)
                root.applyDnsStatus(dnsOutput.text);
            else
                root.clearDns();
        }
    }

    Timer {
        interval: 2000
        running: root.queriesEnabled && !root.atHome
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
