import QtQuick
import Quickshell
import Quickshell.Io

import "../WifiUtils.js" as WifiUtils

// Owns NetworkManager mutations, output classification, refresh delay, and cleanup.
Scope {
    id: root

    property bool busy: false

    signal started
    signal succeeded
    signal passwordRequired
    signal failed(string details)
    signal refreshRequested

    function runWithExit(commandText) {
        if (root.busy)
            return;
        root.busy = true;
        root.started();
        runner.command = ["bash", "-c", commandText + " 2>&1; rc=$?; echo __EXIT:$rc"];
        runner.running = true;
    }

    // New profiles are transactional: preserve original command status, delete
    // profile by ID only on failure, then return that status to output classifier.
    function runNewConnection(commandText, ssid) {
        const cleanup = "rc=$?; if [ $rc -ne 0 ]; then nmcli connection delete id " + WifiUtils.shellQuote(ssid) + " >/dev/null 2>&1; fi; (exit $rc)";
        root.runWithExit("{ " + commandText + "; } 2>&1; " + cleanup);
    }

    function connectSaved(uuid, ssid) {
        if (!uuid || uuid === "") {
            root.failed("Invalid connection");
            return;
        }

        root.runWithExit("nmcli -w 15 connection up uuid " + WifiUtils.shellQuote(uuid));
    }

    function setSavedPskAndConnect(uuid, password) {
        root.runWithExit("nmcli connection modify uuid " + WifiUtils.shellQuote(uuid) + " 802-11-wireless-security.key-mgmt wpa-psk " + " 802-11-wireless-security.psk " + WifiUtils.shellQuote(password) + " && " + "nmcli -w 15 connection up uuid " + WifiUtils.shellQuote(uuid));
    }

    function connectNew(ssid, password, username, isEnterprise) {
        let commandText = "";
        if (isEnterprise) {
            // dev wifi connect cannot set 802-1x fields. Rebuild PEAP/MSCHAPv2
            // explicitly so retries replace stale or half-created profiles.
            commandText = "nmcli connection delete id " + WifiUtils.shellQuote(ssid) + " 2>/dev/null; " + "nmcli connection add type wifi con-name " + WifiUtils.shellQuote(ssid) + " ifname '*' ssid " + WifiUtils.shellQuote(ssid) + " wifi-sec.key-mgmt wpa-eap" + " 802-1x.eap peap" + " 802-1x.phase2-auth mschapv2" + " 802-1x.identity " + WifiUtils.shellQuote(username) + " 802-1x.password " + WifiUtils.shellQuote(password) + " && nmcli -w 25 connection up id " + WifiUtils.shellQuote(ssid);
        } else {
            commandText = "nmcli -w 20 dev wifi connect " + WifiUtils.shellQuote(ssid);
            if (password && password.trim().length > 0)
                commandText += " password " + WifiUtils.shellQuote(password);
        }

        root.runNewConnection(commandText, ssid);
    }

    function toggleWifi(wifiEnabled) {
        if (root.busy)
            return;
        root.runWithExit("nmcli radio wifi " + (wifiEnabled ? "off" : "on"));
    }

    function disconnectNetwork(activeConnectionUuid) {
        if (root.busy)
            return;
        if (!activeConnectionUuid || activeConnectionUuid === "") {
            root.failed("No active connection");
            return;
        }
        root.runWithExit("nmcli connection down uuid " + WifiUtils.shellQuote(activeConnectionUuid));
    }

    function openAdvancedEditor() {
        Quickshell.execDetached(["nm-connection-editor"]);
    }

    // Successful actions retain their separate delayed status refresh. Process
    // lifecycle signals let the controller own the original shared watchdog.
    Timer {
        id: statusRefreshDelay
        interval: 1500
        repeat: false
        onTriggered: root.refreshRequested()
    }

    // Every shell action appends __EXIT:<status>. Secret errors have dedicated
    // routing; generic failures expose only final ten lines, matching current UI.
    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const output = String(text || "");
                const ok = output.includes("__EXIT:0");

                if (ok) {
                    root.succeeded();
                    statusRefreshDelay.restart();
                    return;
                }

                if (output.includes("Secrets were required") || output.includes("No suitable secrets")) {
                    root.passwordRequired();
                    return;
                }

                const lines = output.trim().split(/\r?\n/);
                const tail = lines.slice(Math.max(0, lines.length - 10)).join("\n");
                root.failed(tail.length ? tail : "Connection failed. Check credentials and try again.");
                root.refreshRequested();
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.busy) {
                root.busy = false;
                root.failed("");
            }
        }
    }
}
