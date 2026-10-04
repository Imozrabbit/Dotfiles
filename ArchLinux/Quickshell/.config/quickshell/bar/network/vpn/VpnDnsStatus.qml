import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "VpnDns.js" as VpnDns

Scope {
    id: root

    property var routerManagedSsids: []
    property bool queriesEnabled: true
    readonly property var activeSsids: Networking.devices.values.filter(device => device.type === DeviceType.Wifi).map(device => device.networks.values.find(network => network.connected)?.name ?? "").filter(name => name !== "")
    property var connections: null
    property var devices: null
    property var dnsRows: null
    readonly property var vpn: VpnDns.vpnState(root.connections, root.activeSsids, root.routerManagedSsids)
    readonly property var dns: VpnDns.classifyDns(root.dnsRows, root.devices, root.connections)
    readonly property string protectionMode: root.vpn.mode
    readonly property string vpnName: root.vpn.name
    readonly property string dnsKind: root.dns.kind
    readonly property string dnsName: root.dns.name
    readonly property string dnsServers: root.dns.servers

    property int generation: 0
    property int requestGeneration: -1
    property int pending: 0
    property bool timedOut: false
    property var nextConnections: null
    property var nextDevices: null
    property var nextDnsRows: null

    function refresh() {
        if (!root.queriesEnabled || root.pending !== 0 || vpnProcess.running || deviceProcess.running || dnsProcess.running)
            return;
        root.requestGeneration = root.generation;
        root.nextConnections = null;
        root.nextDevices = null;
        root.nextDnsRows = null;
        root.timedOut = false;
        root.pending = 3;
        vpnProcess.requestDone = false;
        deviceProcess.requestDone = false;
        dnsProcess.requestDone = false;
        timeout.restart();
        vpnProcess.running = true;
        deviceProcess.running = true;
        dnsProcess.running = true;
    }

    function complete(process, field, value) {
        if (process.requestDone)
            return;
        process.requestDone = true;
        root[field] = value;
        root.finish();
    }

    function finish() {
        root.pending--;
        if (root.pending !== 0)
            return;
        timeout.stop();
        if (root.requestGeneration !== root.generation) {
            Qt.callLater(root.refresh);
            return;
        }
        root.connections = root.nextConnections;
        root.devices = root.nextDevices;
        root.dnsRows = root.nextDnsRows;
    }

    onActiveSsidsChanged: {
        root.generation++;
        root.connections = null;
        root.devices = null;
        root.dnsRows = null;
        Qt.callLater(root.refresh);
    }

    Process {
        id: vpnProcess
        property bool requestDone: true
        command: ["nmcli", "--wait", "2", "--terse", "--escape", "yes", "--fields", "UUID,NAME,TYPE,DEVICE", "connection", "show", "--active"]
        stdout: StdioCollector {
            id: vpnOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.complete(vpnProcess, "nextConnections", exitCode === 0 && !root.timedOut ? VpnDns.parseConnections(vpnOutput.text) : null);
        }
        onRunningChanged: {
            if (!vpnProcess.running)
                root.complete(vpnProcess, "nextConnections", null);
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: deviceProcess
        property bool requestDone: true
        command: ["nmcli", "--wait", "2", "--terse", "--escape", "yes", "--fields", "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.GATEWAY,IP6.GATEWAY", "device", "show"]
        stdout: StdioCollector {
            id: deviceOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.complete(deviceProcess, "nextDevices", exitCode === 0 && !root.timedOut ? VpnDns.parseDevices(deviceOutput.text) : null);
        }
        onRunningChanged: {
            if (!deviceProcess.running)
                root.complete(deviceProcess, "nextDevices", null);
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: dnsProcess
        property bool requestDone: true
        command: ["resolvectl", "status"]
        // Process accepts a JS environment object; qmllint cannot infer QVariantHash conversion.
        // qmllint disable incompatible-type
        environment: ({
                LC_ALL: "C"
            })
        // qmllint enable incompatible-type
        stdout: StdioCollector {
            id: dnsOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.complete(dnsProcess, "nextDnsRows", exitCode === 0 && !root.timedOut ? VpnDns.parseDnsStatus(dnsOutput.text) : null);
        }
        onRunningChanged: {
            if (!dnsProcess.running)
                root.complete(dnsProcess, "nextDnsRows", null);
        }
        // qmllint enable signal-handler-parameters
    }

    Timer {
        interval: 2000
        running: root.queriesEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: timeout
        interval: 3000
        onTriggered: {
            root.timedOut = true;
            if (vpnProcess.running)
                vpnProcess.running = false;
            if (deviceProcess.running)
                deviceProcess.running = false;
            if (dnsProcess.running)
                dnsProcess.running = false;
        }
    }
}
