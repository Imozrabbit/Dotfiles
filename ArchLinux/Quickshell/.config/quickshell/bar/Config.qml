import QtQuick
import Quickshell
import Quickshell.Io

import "core/BarConfig.js" as BarConfig

Scope {
    id: root

    readonly property string localPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/bar-local.json"
    readonly property var defaults: ({
            mode: "always",
            hoverToggleEnabled: true,
            modules: {
                workspaces: true,
                tray: true,
                launcher: true,
                updates: true,
                media: true,
                network: true,
                vpn: true,
                wifiMenu: true,
                cpu: true,
                gpu: true,
                memory: true,
                volume: true,
                bluetooth: true,
                inputMethod: true,
                brightness: true,
                battery: true,
                clock: true,
                calendar: true,
                weather: true,
                notifications: true
            },
            workspaceDisplay: {
                minimumCount: 3,
                normalLabels: {},
                specialLabels: {}
            }
        })
    property var settings: BarConfig.resolveConfig(root.defaults, "{}")
    property bool ready: false

    function forScreen(name) {
        return BarConfig.screenConfig(root.settings, name);
    }

    Process {
        id: localConfigProcess

        command: ["sh", "-c", "if [ -r \"$1\" ]; then cat -- \"$1\"; else printf '{}'; fi", "sh", root.localPath]
        running: true
        stdout: StdioCollector {
            id: localConfigOutput
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            if (exitCode === 0)
                root.settings = BarConfig.resolveConfig(root.defaults, localConfigOutput.text);
            root.ready = true;
        }
        // qmllint enable signal-handler-parameters
    }

    Timer {
        interval: 3000
        running: !root.ready
        repeat: false
        onTriggered: {
            localConfigProcess.running = false;
            root.ready = true;
        }
    }
}
