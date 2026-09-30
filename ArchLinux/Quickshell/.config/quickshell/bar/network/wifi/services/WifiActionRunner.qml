import QtQuick
import Quickshell
import Quickshell.Io

import "../WifiUtils.js" as WifiUtils

// Owns NetworkManager mutations, output classification, and refresh delay.
Scope {
    id: root

    property bool busy: false
    property string actionKind: ""

    signal started
    signal succeeded
    signal passwordRequired
    signal failed(string details)
    signal refreshRequested
    signal radioToggleSucceeded
    signal radioToggleFailed(string details)

    function runWithExit(commandText, kind) {
        if (root.busy)
            return;
        root.busy = true;
        root.actionKind = kind || "";
        root.started();
        runner.command = ["bash", "-c", commandText + " 2>&1; rc=$?; echo __EXIT:$rc"];
        runner.running = true;
    }

    function connectSaved(uuid) {
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
        if (isEnterprise) {
            root.failed("Enterprise WiFi setup requires NetworkManager settings");
            return;
        }

        let commandText = "nmcli -w 20 dev wifi connect " + WifiUtils.shellQuote(ssid);
        if (password && password.trim().length > 0)
            commandText += " password " + WifiUtils.shellQuote(password);

        root.runWithExit(commandText);
    }

    function toggleWifi(wifiEnabled) {
        if (root.busy)
            return;
        root.runWithExit("nmcli radio wifi " + (wifiEnabled ? "off" : "on"), "radio");
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
                runner.command = [];
                const marker = output.match(/(?:^|\n)__EXIT:(\d+)\s*$/);
                const ok = marker !== null && Number(marker[1]) === 0;
                const kind = root.actionKind;
                root.actionKind = "";

                if (ok) {
                    if (kind === "radio") {
                        root.radioToggleSucceeded();
                        return;
                    }
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
                if (kind === "radio") {
                    root.radioToggleFailed(tail.length ? tail : "WiFi toggle failed");
                    return;
                }
                root.failed(tail.length ? tail : "Connection failed. Check credentials and try again.");
                root.refreshRequested();
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            if (exitCode !== 0 && root.busy) {
                root.busy = false;
                const kind = root.actionKind;
                root.actionKind = "";
                if (kind === "radio")
                    root.radioToggleFailed("");
                else
                    root.failed("");
            }
        }
        // qmllint enable signal-handler-parameters
    }
}
