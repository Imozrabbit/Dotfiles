import QtQuick
import Quickshell
import Quickshell.Io

import "core/BarConfig.js" as BarConfig

Scope {
    id: root

    readonly property string localPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/bar-local.json"
    readonly property var defaults: ({
            mode: "always",
            topMediaMode: "hover",
            edgeSpacing: 14,
            hoverToggleEnabled: true,
            vpn: {
                routerManagedSsids: []
            },
            protonManager: {
                compatibilityToolsDir: "/home/Steam/.local/share/Steam/compatibilitytools.d",
                umuConfigPath: "/home/Steam/.config/umu-launcher/config.toml",
                sandboxCompatibilityToolsDir: "/home/Zrabbit/.local/share/Steam/compatibilitytools.d"
            },
            mouseBattery: {
                name: "WLMouse Beast X"
            },
            launchers: [
                {
                    icon: "󰸉",
                    tooltip: "Wallpaper Switcher",
                    leftCommand: ["quickshell", "-c", "wallpaper_switcher"],
                    rightCommand: []
                },
                {
                    icon: "󰔎",
                    tooltip: "Left click: GTK Look\nRight click: Qt6ct",
                    leftCommand: ["nwg-look"],
                    rightCommand: ["qt6ct"]
                }
            ],
            modules: {
                workspaces: true,
                tray: true,
                launcher: true,
                updates: true,
                protonManager: false,
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
                mouseBattery: false,
                openAiUsage: false,
                clock: true,
                calendar: true,
                weather: true,
                notifications: true
            },
            workspaceDisplay: {
                minimumCount: 3,
                itemSpacing: 21,
                normalLabels: {},
                specialLabels: {}
            }
        })
    property var settings: BarConfig.resolveConfig(root.defaults, "{}")
    property bool ready: false

    function forScreen(name) {
        return BarConfig.screenConfig(root.settings, name);
    }

    FileView {
        id: localConfig
        path: root.localPath
        watchChanges: true
        printErrors: false
        onFileChanged: reloadDelay.restart()
        onLoaded: {
            const next = BarConfig.resolveConfig(root.defaults, text(), root.settings);
            if (next === root.settings)
                console.warn("Invalid bar-local.json; keeping last valid configuration");
            else
                root.settings = next;
            root.ready = true;
        }
        onLoadFailed: {
            // Missing/unreadable files keep defaults at startup or the last live settings.
            root.ready = true;
        }
    }

    Timer {
        id: reloadDelay
        interval: 150
        repeat: false
        onTriggered: localConfig.reload()
    }

    Timer {
        interval: 3000
        running: !root.ready
        repeat: false
        onTriggered: root.ready = true
    }
}
