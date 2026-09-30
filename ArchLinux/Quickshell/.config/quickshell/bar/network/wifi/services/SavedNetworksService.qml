import QtQuick
import Quickshell
import Quickshell.Io

// Owns saved NetworkManager profile loading and SSID lookup.
Scope {
    id: root

    property alias model: savedModel
    property var bySsid: Object.create(null)
    property bool refreshQueued: false

    signal refreshed

    function refresh() {
        if (savedProcess.running) {
            root.refreshQueued = true;
            return;
        }
        savedProcess.running = true;
    }

    ListModel {
        id: savedModel
    }

    // nmcli -g emits requested fields on separate lines. Shell normalizes each
    // wireless profile into uuid<TAB>ssid<TAB>name; parser rejects partial rows
    // and keeps the first profile found for each SSID.
    Process {
        id: savedProcess
        command: ["bash", "-c", `
        nmcli -t -f UUID,TYPE connection show 2>/dev/null \
        | awk -F: '$2=="802-11-wireless"{print $1}' \
        | while IFS= read -r uuid; do
            # nmcli -g prints ONE LINE PER FIELD, so read all profile fields
            mapfile -t vals < <(nmcli -g 802-11-wireless.ssid,connection.id,802-11-wireless-security.key-mgmt connection show uuid "$uuid" 2>/dev/null)

            ssid="\${vals[0]}"
            name="\${vals[1]}"
            key_mgmt="\${vals[2]}"

            # fallbacks for weird/empty profiles
            [ -z "$name" ] && name="$ssid"
            [ -z "$ssid" ] && ssid="$name"
            [ -z "$ssid" ] && continue

            # Emit tab-separated: uuid<TAB>ssid<TAB>name<TAB>key management
            printf '%s\\t%s\\t%s\\t%s\\n' "$uuid" "$ssid" "$name" "$key_mgmt"
        done
    `]
        stdout: StdioCollector {
            onStreamFinished: {
                savedModel.clear();
                root.bySsid = Object.create(null);

                const lines = String(text || "").split(/\r?\n/);
                for (let line of lines) {
                    if (!line.trim())
                        continue;
                    const parts = line.split("\t");
                    if (parts.length < 4)
                        continue;
                    const uuid = parts[0].trim();
                    const ssid = parts[1];
                    const name = parts[2];
                    const keyManagement = parts[3];

                    if (!uuid || !ssid)
                        continue;
                    if (root.bySsid[ssid] === undefined) {
                        savedModel.append({
                            ssid,
                            name,
                            uuid,
                            isEnterprise: keyManagement === "wpa-eap" || keyManagement === "wpa-eap-suite-b-192"
                        });
                        root.bySsid[ssid] = {
                            uuid,
                            isEnterprise: keyManagement === "wpa-eap" || keyManagement === "wpa-eap-suite-b-192"
                        };
                    }
                }

                root.refreshed();
                if (root.refreshQueued) {
                    root.refreshQueued = false;
                    Qt.callLater(root.refresh);
                }
            }
        }
    }
}
