import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "VpnDns.js" as VpnDns

Scope {
    id: root

    property var routerManagedSsids: []
    property string schoolService: ""
    property string schoolInterface: "ppp0"
    property string schoolName: "School VPN"
    property string schoolServiceText: ""
    property string schoolInterfaceText: ""
    property bool schoolAvailable: false
    readonly property var school: root.schoolService === "" ? null : ({
            name: root.schoolName,
            state: VpnDns.schoolState(root.schoolAvailable ? root.schoolServiceText : null, root.schoolAvailable ? root.schoolInterfaceText : null, root.schoolInterface)
        })
    property bool queriesEnabled: true
    readonly property var activeSsids: Networking.devices.values.filter(device => device.type === DeviceType.Wifi).map(device => device.networks.values.find(network => network.connected)?.name ?? "").filter(name => name !== "")
    property var connections: null
    property var devices: null
    property var dnsRows: null
    readonly property var vpn: VpnDns.vpnState(root.connections, root.activeSsids, root.routerManagedSsids, root.school)
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
    property var nextSchoolService: null
    property var nextSchoolInterface: null

    function refresh() {
        if (!root.queriesEnabled || root.pending !== 0 || vpnProcess.running || deviceProcess.running || dnsProcess.running || schoolProcess.running || interfaceProcess.running)
            return;
        root.requestGeneration = root.generation;
        root.nextConnections = null;
        root.nextDevices = null;
        root.nextDnsRows = null;
        root.nextSchoolService = null;
        root.nextSchoolInterface = null;
        root.timedOut = false;
        root.pending = root.schoolService === "" ? 3 : 5;
        vpnProcess.requestDone = false;
        deviceProcess.requestDone = false;
        dnsProcess.requestDone = false;
        schoolProcess.requestDone = root.schoolService === "";
        interfaceProcess.requestDone = root.schoolService === "";
        timeout.restart();
        vpnProcess.running = true;
        deviceProcess.running = true;
        dnsProcess.running = true;
        if (root.schoolService !== "") {
            schoolProcess.running = true;
            interfaceProcess.running = true;
        }
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
        root.schoolAvailable = root.nextSchoolService !== null && root.nextSchoolInterface !== null;
        root.schoolServiceText = root.nextSchoolService ?? "";
        root.schoolInterfaceText = root.nextSchoolInterface ?? "";
    }

    onActiveSsidsChanged: {
        root.generation++;
        root.connections = null;
        root.devices = null;
        root.dnsRows = null;
        root.schoolAvailable = false;
        Qt.callLater(root.refresh);
    }

    function schoolConfigChanged() {
        root.generation++;
        root.schoolAvailable = false;
        Qt.callLater(root.refresh);
    }
    onSchoolServiceChanged: root.schoolConfigChanged()
    onSchoolInterfaceChanged: root.schoolConfigChanged()

    Process {
        id: schoolProcess
        property bool requestDone: true
        command: ["systemctl", "show", "--no-pager", "--property=LoadState,ActiveState,SubState,Type", "--", root.schoolService]
        stdout: StdioCollector {
            id: schoolOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.complete(schoolProcess, "nextSchoolService", exitCode === 0 && !root.timedOut ? schoolOutput.text : null);
        }
        onRunningChanged: {
            if (!schoolProcess.running)
                root.complete(schoolProcess, "nextSchoolService", null);
        }
        // qmllint enable signal-handler-parameters
    }

    Process {
        id: interfaceProcess
        property bool requestDone: true
        command: ["ip", "-j", "address", "show"]
        stdout: StdioCollector {
            id: interfaceOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.complete(interfaceProcess, "nextSchoolInterface", exitCode === 0 && !root.timedOut ? interfaceOutput.text : null);
        }
        onRunningChanged: {
            if (!interfaceProcess.running)
                root.complete(interfaceProcess, "nextSchoolInterface", null);
        }
        // qmllint enable signal-handler-parameters
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
            if (schoolProcess.running)
                schoolProcess.running = false;
            if (interfaceProcess.running)
                interfaceProcess.running = false;
        }
    }
}
