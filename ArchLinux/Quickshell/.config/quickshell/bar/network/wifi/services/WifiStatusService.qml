import QtQuick
import Quickshell
import Quickshell.Io

// Owns live NetworkManager status collection and last-known status persistence.
Scope {
    id: root

    readonly property string statusCachePath: Quickshell.env("HOME") + "/.cache/quickshell/wifi_status.json"
    property bool wifiEnabled: true
    property string activeConnectionUuid: ""
    property string currentSsid: "Checking…"
    property int currentSignal: 0
    property string currentIp: ""
    property bool statusLoaded: false
    property string lastStatusCacheJson: ""
    property bool refreshQueued: false
    property int refreshGeneration: 0

    signal refreshed(int generation)

    function refresh() {
        if (statusProcess.running) {
            root.refreshQueued = true;
            return root.refreshGeneration + 1;
        }

        root.refreshGeneration++;
        statusProcess.running = true;
        return root.refreshGeneration;
    }

    // Cache preload may finish after nmcli. Live status always wins, and malformed
    // or partial JSON only updates fields whose existing types match the contract.
    function applyStatusCache(raw) {
        if (root.statusLoaded)
            return;
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (!data)
            return;
        if (typeof data.wifiEnabled === "boolean")
            root.wifiEnabled = data.wifiEnabled;
        if (typeof data.ssid === "string" && data.ssid.length > 0)
            root.currentSsid = data.ssid;
        if (typeof data.signal === "number")
            root.currentSignal = data.signal;
        if (typeof data.ip === "string")
            root.currentIp = data.ip;
        if (typeof data.uuid === "string")
            root.activeConnectionUuid = data.uuid;
    }

    // Persist resolved changes atomically and avoid duplicate writes.
    function writeStatusCache() {
        const data = {
            wifiEnabled: root.wifiEnabled,
            ssid: root.currentSsid,
            signal: root.currentSignal,
            ip: root.currentIp,
            uuid: root.activeConnectionUuid
        };
        const json = JSON.stringify(data);

        if (json === root.lastStatusCacheJson)
            return;
        root.lastStatusCacheJson = json;

        statusCache.setText(json);
    }

    FileView {
        id: statusCache
        path: root.statusCachePath
        preload: true
        blockWrites: true
        atomicWrites: true
        onLoaded: root.applyStatusCache(text())
    }

    // Output contract is one KEY:value line per status field. Values may contain
    // colons, so parsing splits only the key and rejoins the remaining segments.
    Process {
        id: statusProcess
        command: ["bash", "-c", `
            # Get WiFi radio state
            WIFI_STATE=$(nmcli -g WIFI radio 2>/dev/null || echo "unknown")
            echo "WIFI:$WIFI_STATE"

            if [ "$WIFI_STATE" != "enabled" ]; then
                exit 0
            fi

            # Get active WiFi connection UUID and state
            ACTIVE_CONNECTIONS=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null)
            ACTIVE=$(printf '%s\\n' "$ACTIVE_CONNECTIONS" | awk -F: '$2=="802-11-wireless" && $3=="activated"{print $1; exit}')

            if [ -z "$ACTIVE" ]; then
                # Check for activating connections
                ACTIVATING=$(printf '%s\\n' "$ACTIVE_CONNECTIONS" | awk -F: '$2=="802-11-wireless" && $3=="activating"{print $1; exit}')
                if [ -n "$ACTIVATING" ]; then
                    echo "UUID:$ACTIVATING"
                    echo "STATE:activating"
                    exit 0
                fi
                echo "STATE:disconnected"
                exit 0
            fi

            echo "UUID:$ACTIVE"
            echo "STATE:activated"

            # Get SSID from connection
            SSID=$(nmcli -g 802-11-wireless.ssid connection show uuid "$ACTIVE" 2>/dev/null | head -n1)
            echo "SSID:$SSID"

            # Get signal strength
            SIGNAL=$(nmcli -g IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')
            echo "SIGNAL:$SIGNAL"

            # Get IP address
            DEVICE=$(nmcli -g GENERAL.DEVICES connection show uuid "$ACTIVE" 2>/dev/null | head -n1)
            IP=$(ip -o -4 addr show dev "$DEVICE" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="inet"){print $(i+1); exit}}')
            echo "IP:$IP"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split(/\r?\n/);
                let wifi = "", uuid = "", state = "", ssid = "", signal = "", ip = "";

                for (let line of lines) {
                    const parts = line.trim().split(":");
                    if (parts.length < 2)
                        continue;
                    const key = parts[0];
                    const value = parts.slice(1).join(":");

                    if (key === "WIFI")
                        wifi = value;
                    else if (key === "UUID")
                        uuid = value;
                    else if (key === "STATE")
                        state = value;
                    else if (key === "SSID")
                        ssid = value;
                    else if (key === "SIGNAL")
                        signal = value;
                    else if (key === "IP")
                        ip = value;
                }

                if (wifi !== "enabled" && wifi !== "disabled") {
                    root.refreshed(root.refreshGeneration);
                    if (root.refreshQueued) {
                        root.refreshQueued = false;
                        Qt.callLater(root.refresh);
                    }
                    return;
                }

                root.statusLoaded = true;
                root.wifiEnabled = wifi === "enabled";

                if (!root.wifiEnabled) {
                    root.currentSsid = "WiFi Off";
                    root.currentIp = "";
                    root.currentSignal = 0;
                    root.activeConnectionUuid = "";
                    root.writeStatusCache();
                } else {
                    root.activeConnectionUuid = uuid;

                    if (state === "activated") {
                        root.currentSsid = ssid || "Connected";
                        const parsedSignal = parseInt(signal, 10);
                        root.currentSignal = isFinite(parsedSignal) ? parsedSignal : 0;
                        root.currentIp = ip;
                    } else if (state === "activating") {
                        root.currentSsid = "Connecting…";
                        root.currentIp = "";
                        root.currentSignal = 0;
                    } else {
                        root.currentSsid = "Disconnected";
                        root.currentIp = "";
                        root.currentSignal = 0;
                    }

                    if (state !== "activating")
                        root.writeStatusCache();
                }

                root.refreshed(root.refreshGeneration);
                if (root.refreshQueued) {
                    root.refreshQueued = false;
                    Qt.callLater(root.refresh);
                }
            }
        }
    }
}
