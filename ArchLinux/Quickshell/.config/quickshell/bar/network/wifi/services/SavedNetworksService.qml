import QtQuick
import Quickshell
import Quickshell.Io

// Owns saved NetworkManager profile loading and SSID lookup.
Scope {
    id: root

    property alias model: savedModel
    property var bySsid: ({})

    signal refreshed

    function refresh() {
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
            # nmcli -g prints ONE LINE PER FIELD, so read both lines
            mapfile -t vals < <(nmcli -g 802-11-wireless.ssid,connection.id connection show uuid "$uuid" 2>/dev/null)

            ssid="\${vals[0]}"
            name="\${vals[1]}"

            # fallbacks for weird/empty profiles
            [ -z "$name" ] && name="$ssid"
            [ -z "$ssid" ] && ssid="$name"
            [ -z "$ssid" ] && continue

            # Emit tab-separated: uuid<TAB>ssid<TAB>name
            printf '%s\\t%s\\t%s\\n' "$uuid" "$ssid" "$name"
        done
    `]
        stdout: StdioCollector {
            onStreamFinished: {
                savedModel.clear();
                root.bySsid = ({});

                const lines = String(text || "").split(/\r?\n/);
                for (let line of lines) {
                    if (!line.trim())
                        continue;
                    const parts = line.split("\t");
                    if (parts.length < 3)
                        continue;
                    const uuid = parts[0].trim();
                    const ssid = parts[1].trim();
                    const name = parts[2].trim();

                    if (!uuid || !ssid)
                        continue;
                    if (root.bySsid[ssid] === undefined) {
                        savedModel.append({
                            ssid,
                            name,
                            uuid
                        });
                        root.bySsid[ssid] = {
                            uuid
                        };
                    }
                }

                root.refreshed();
            }
        }
    }
}
