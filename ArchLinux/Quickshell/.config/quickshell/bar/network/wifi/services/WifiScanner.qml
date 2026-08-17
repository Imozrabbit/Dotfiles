import QtQuick
import Quickshell
import Quickshell.Io

import "../WifiUtils.js" as WifiUtils

// Owns access-point scanning, nmcli parsing, and strongest-BSSID deduplication.
Scope {
    id: root

    property alias model: networkModel
    property bool scanRunning: false
    property var ssidMap: ({})

    signal scanStarted
    signal scanCompleted
    signal scanFailed

    function clear() {
        networkModel.clear();
        root.ssidMap = ({});
    }

    function scan() {
        root.scanRunning = true;
        root.scanStarted();
        scanner.running = true;
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

    // nmcli escapes colons inside all four colon-delimited fields. Temporarily
    // replacing escaped delimiters preserves BSSIDs and names before conversion.
    function parseScanOutput(raw) {
        const lines = String(raw || "").split(/\r?\n/);
        for (let line of lines) {
            line = line.trim();
            if (!line)
                continue;

            const safeLine = line.replace(/\\:/g, "___COLON___");
            const parts = safeLine.split(":");
            if (parts.length < 4)
                continue;
            const bssid = parts[0].replace(/___COLON___/g, ":");
            const ssid = parts[1].replace(/___COLON___/g, ":");
            const security = parts[2].replace(/___COLON___/g, ":");
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
            onStreamFinished: {
                root.scanRunning = false;
                root.parseScanOutput(text || "");
                root.scanCompleted();
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.scanRunning) {
                root.scanRunning = false;
                root.scanFailed();
            }
        }
    }
}
