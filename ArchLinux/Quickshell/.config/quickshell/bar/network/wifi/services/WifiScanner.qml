import QtQuick
import Quickshell
import Quickshell.Io

import "../WifiUtils.js" as WifiUtils

// Owns access-point scanning, nmcli parsing, and strongest-BSSID deduplication.
Scope {
    id: root

    property alias model: networkModel
    property bool scanRunning: false
    property bool scanQueued: false
    property var ssidMap: Object.create(null)
    property bool outputFinished: false
    property int exitCode: -1

    signal scanStarted
    signal scanCompleted
    signal scanFailed

    function clear() {
        networkModel.clear();
        root.ssidMap = Object.create(null);
    }

    function scan() {
        if (scanner.running) {
            root.scanQueued = true;
            return;
        }
        root.scanRunning = true;
        root.outputFinished = false;
        root.exitCode = -1;
        root.scanStarted();
        scanner.running = true;
    }

    function finishScan() {
        if (!root.outputFinished || root.exitCode < 0)
            return;
        root.scanRunning = false;
        if (root.exitCode === 0) {
            root.parseScanOutput(scanOutput.text || "");
            if (root.scanQueued) {
                root.scanQueued = false;
                Qt.callLater(root.scan);
            } else {
                root.scanCompleted();
            }
        } else {
            root.scanQueued = false;
            root.scanFailed();
        }
    }

    function upsertNetwork(ssid, bssid, security, signal) {
        if (!ssid || ssid.length === 0)
            return;
        if (!bssid || bssid.length === 0)
            return;
        const enterprise = WifiUtils.securityIsEnterprise(security);

        if (root.ssidMap[ssid] !== undefined) {
            const index = root.ssidMap[ssid];
            if (index < networkModel.count) {
                const current = networkModel.get(index);
                if (signal > current.strength) {
                    networkModel.setProperty(index, "security", security || "");
                    networkModel.setProperty(index, "strength", signal);
                    networkModel.setProperty(index, "isEnterprise", enterprise);
                }
            }
            return;
        }

        networkModel.append({
            ssid: ssid,
            security: security || "",
            strength: signal,
            isEnterprise: enterprise
        });
        root.ssidMap[ssid] = networkModel.count - 1;
    }

    function parseEscapedFields(line) {
        const fields = [];
        let field = "";
        for (let index = 0; index < line.length; index++) {
            const character = line[index];
            if (character === "\\" && index + 1 < line.length) {
                field += line[++index];
            } else if (character === ":") {
                fields.push(field);
                field = "";
            } else {
                field += character;
            }
        }
        fields.push(field);
        return fields;
    }

    // Parse nmcli's escaped colon-delimited output without sentinel strings.
    function parseScanOutput(raw) {
        const lines = String(raw || "").split(/\r?\n/);
        for (let line of lines) {
            line = line.trim();
            if (!line)
                continue;

            const parts = root.parseEscapedFields(line);
            if (parts.length < 4)
                continue;
            const bssid = parts[0];
            const ssid = parts[1];
            const security = parts[2];
            const signalText = parts[3];

            let signal = parseInt(signalText, 10);
            if (!isFinite(signal))
                signal = 0;
            if (!ssid || ssid.length === 0)
                continue;
            root.upsertNetwork(ssid, bssid, security, signal);
        }
    }

    ListModel {
        id: networkModel
    }

    // Output contract is BSSID:SSID:SECURITY:SIGNAL from nmcli -g. Stream
    // completion owns parsed results; lifecycle signals let the controller manage
    // the one watchdog shared with action processes in the original menu.
    Process {
        id: scanner
        command: ["bash", "-c", "nmcli -g BSSID,SSID,SECURITY,SIGNAL dev wifi list --rescan yes 2>/dev/null"]
        stdout: StdioCollector {
            id: scanOutput
            onStreamFinished: {
                root.outputFinished = true;
                root.finishScan();
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.exitCode = exitCode;
            root.finishScan();
        }
        // qmllint enable signal-handler-parameters
    }
}
