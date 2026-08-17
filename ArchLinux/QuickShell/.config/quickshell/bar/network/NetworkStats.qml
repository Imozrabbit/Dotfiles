import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Scope {
    id: root

    property string interfaceName: ""
    property real downloadBps
    property real uploadBps
    property bool online: false

    property real lastRxBytes: -1
    property real lastTxBytes: -1
    property real lastSampleTime: 0

    // The default route identifies which network interface currently carries internet traffic.
    readonly property var activeDevice: Networking.devices.values.find(device => device.name === root.interfaceName)
    readonly property string connectionType: {
        if (!activeDevice)
            return "unknown";
        if (activeDevice.type === DeviceType.Wifi)
            return "wifi";
        if (activeDevice.type === DeviceType.Wired)
            return "wired";
        return "unknown";
    }

    readonly property var activeNetwork: activeDevice && connectionType === "wifi" ? activeDevice.networks.values.find(network => network.connected) : null
    readonly property int signalPercent: activeNetwork ? Math.round(Math.max(0, Math.min(1, activeNetwork.signalStrength)) * 100) : -1

    readonly property string networkName: activeNetwork ? activeNetwork.name : ""
    property string gatewayAddress: ""

    property alias ipAddressCidr: networkDetails.ipAddressCidr
    property alias frequencyMhz: networkDetails.frequencyMhz

    function refreshDetails() {
        networkDetails.refreshDetails();
    }

    function updateInterface(nextInterface) {
        if (nextInterface === root.interfaceName)
            return;

        root.interfaceName = nextInterface;
        root.ipAddressCidr = "";
        root.frequencyMhz = 0;
        root.downloadBps = 0;
        root.uploadBps = 0;
        root.online = false;
        root.lastRxBytes = -1;
        root.lastTxBytes = -1;
        root.lastSampleTime = 0;
    }

    function ipv4FromLittleEndian(value) {
        return [value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff].join(".");
    }

    // When several default routes exist, the lowest metric means highest priority.
    function selectDefaultRoute(routeText) {
        const lines = routeText.trim().split("\n");
        let bestInterface = "";
        let bestGateway = "";
        let bestMetric = Infinity;

        for (let i = 1; i < lines.length; i++) {
            const fields = lines[i].trim().split(/\s+/);
            if (fields.length < 8)
                continue;

            const gateway = parseInt(fields[2], 16);
            const flags = parseInt(fields[3], 16);
            const metric = Number(fields[6]);

            if (fields[1] !== "00000000" || !isFinite(gateway) || gateway === 0 || !isFinite(flags) || (flags & 0x3) !== 0x3 || !isFinite(metric) || metric >= bestMetric)
                continue;

            bestInterface = fields[0];
            bestMetric = metric;
            bestGateway = root.ipv4FromLittleEndian(gateway);
        }
        return {
            interfaceName: bestInterface,
            gatewayAddress: bestGateway
        };
    }

    function parseInterfaceCounters(netDevText, interfaceName) {
        if (interfaceName === "")
            return null;

        const lines = netDevText.split("\n");

        for (let i = 2; i < lines.length; i++) {
            const separator = lines[i].lastIndexOf(":");
            if (separator < 0)
                continue;

            const name = lines[i].slice(0, separator).trim();
            if (name !== interfaceName)
                continue;

            const fields = lines[i].slice(separator + 1).trim().split(/\s+/);
            if (fields.length < 16)
                return null;

            const rxBytes = Number(fields[0]); // received bytes
            const txBytes = Number(fields[8]); // transmitted bytes

            if (!isFinite(rxBytes) || rxBytes < 0 || !isFinite(txBytes) || txBytes < 0)
                return null;

            return {
                rxBytes: rxBytes,
                txBytes: txBytes
            };
        }
        return null;
    }

    // Convert cumulative byte-counter changes into current download and upload rates.
    function sampleInterfaceCounters(netDevText) {
        const counters = root.parseInterfaceCounters(netDevText, root.interfaceName);

        if (counters === null) {
            root.updateInterface("");
            return;
        }

        const now = Date.now();
        const elapsedMs = now - root.lastSampleTime;

        if (root.lastRxBytes >= 0 && root.lastTxBytes >= 0 && elapsedMs > 0 && counters.rxBytes >= root.lastRxBytes && counters.txBytes >= root.lastTxBytes) {
            root.downloadBps = (counters.rxBytes - root.lastRxBytes) * 1000 / elapsedMs;
            root.uploadBps = (counters.txBytes - root.lastTxBytes) * 1000 / elapsedMs;
        } else {
            root.downloadBps = 0;
            root.uploadBps = 0;
        }

        root.lastRxBytes = counters.rxBytes;
        root.lastTxBytes = counters.txBytes;
        root.lastSampleTime = now;
        root.online = true;
    }

    NetworkDetails {
        id: networkDetails
        interfaceName: root.interfaceName
        connectionType: root.connectionType
    }

    // Read the active route first, then sample only that interface's traffic counters.
    FileView {
        id: routeFile
        path: "/proc/net/route"
        printErrors: false

        onLoaded: {
            const route = root.selectDefaultRoute(text());
            root.gatewayAddress = route.gatewayAddress;
            root.updateInterface(route.interfaceName);
            netDevFile.reload();
        }
        onLoadFailed: {
            root.gatewayAddress = "";
            root.updateInterface("");
        }
    }

    FileView {
        id: netDevFile
        path: "/proc/net/dev"
        printErrors: false

        onLoaded: root.sampleInterfaceCounters(text())
        onLoadFailed: root.updateInterface("")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: routeFile.reload()
    }
}
