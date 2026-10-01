//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core as Core
import qs.network as Network
import qs.network.vpn as Vpn
import qs.network.wifi as Wifi
import qs.services as Services

Scope {
    id: root

    property Config barConfig: Config {}
    property Core.Theme theme: Core.Theme {}
    readonly property var cpuStats: cpuLoader.item
    readonly property var gpuStats: gpuLoader.item
    readonly property var updateChecker: updateLoader.item
    readonly property var memoryStats: memoryLoader.item
    readonly property var audioService: audioLoader.item
    readonly property var brightnessService: brightnessLoader.item
    readonly property var fcitx: fcitxLoader.item
    readonly property var swayncService: swayncLoader.item
    readonly property var batteryService: batteryLoader.item
    readonly property var mouseBatteryService: mouseBatteryLoader.item
    readonly property var mprisService: mprisLoader.item
    readonly property var bluetoothService: bluetoothLoader.item
    readonly property var weatherService: weatherLoader.item
    readonly property var networkStats: networkLoader.item
    readonly property var vpnStatus: vpnLoader.item
    readonly property var clock: clockLoader.item
    property bool wifiBarRevealed: true
    readonly property var wifiMenu: wifiLoader.item

    function uses(moduleName) {
        return root.barConfig.ready && Quickshell.screens.some(screen => {
            const config = root.barConfig.forScreen(screen.name);
            return config.mode !== "off" && config.modules[moduleName];
        });
    }

    Connections {
        target: Hyprland
        enabled: root.uses("workspaces")
        function onRawEvent(event) {
            if (event.name === "activespecial")
                Hyprland.refreshMonitors();
        }
    }

    LazyLoader {
        id: cpuLoader
        active: root.uses("cpu")
        Services.CpuStats {}
    }
    LazyLoader {
        id: gpuLoader
        active: root.uses("gpu")
        Services.GpuStats {}
    }
    LazyLoader {
        id: updateLoader
        active: root.uses("updates")
        Services.UpdateCount {}
    }
    LazyLoader {
        id: memoryLoader
        active: root.uses("memory")
        Services.MemoryStats {}
    }
    LazyLoader {
        id: audioLoader
        active: root.uses("volume")
        Services.Audio {}
    }
    LazyLoader {
        id: brightnessLoader
        active: root.uses("brightness")
        Services.Brightness {}
    }
    LazyLoader {
        id: fcitxLoader
        active: root.uses("inputMethod")
        Services.Fcitx {}
    }
    LazyLoader {
        id: swayncLoader
        active: root.uses("notifications")
        Services.Swaync {}
    }
    LazyLoader {
        id: batteryLoader
        active: root.uses("battery") || (root.batteryService?.actionBusy ?? false)
        Services.Battery {
            detailsVisible: outputBars.instances.some(bar => bar.batteryDetailsVisible)
        }
    }
    LazyLoader {
        id: mprisLoader
        active: root.uses("media")
        Services.Mpris {}
    }
    LazyLoader {
        id: mouseBatteryLoader
        active: root.uses("mouseBattery")
        Services.MouseBattery {}
    }
    LazyLoader {
        id: bluetoothLoader
        active: root.uses("bluetooth")
        Services.Bluetooth {}
    }
    LazyLoader {
        id: weatherLoader
        active: root.uses("weather") || (root.weatherService?.loading ?? false) || (root.weatherService?.searching ?? false)
        Services.Weather {}
    }
    LazyLoader {
        id: networkLoader
        active: root.uses("network")
        Network.NetworkStats {}
    }
    LazyLoader {
        id: clockLoader
        active: root.uses("clock") || root.uses("calendar")
        SystemClock {
            precision: SystemClock.Seconds
        }
    }
    LazyLoader {
        id: vpnLoader
        active: root.uses("vpn")
        Vpn.VpnDnsStatus {
            networkName: root.networkStats?.networkName ?? ""
        }
    }
    LazyLoader {
        id: wifiLoader
        active: root.uses("wifiMenu") || (root.wifiMenu?.actionBusy ?? false)
        Wifi.WifiMenu {
            standalone: false
            theme: root.theme
            barRevealed: root.wifiBarRevealed
            onCloseRequested: visible = false
        }
    }

    function openWifi(screen, revealed) {
        if (!root.barConfig.forScreen(screen.name).modules.wifiMenu || !root.wifiMenu)
            return;
        root.wifiBarRevealed = revealed;
        root.wifiMenu.screen = screen;
        root.wifiMenu.visible = !root.wifiMenu.visible;
    }

    Connections {
        target: root.barConfig
        function onSettingsChanged() {
            if (!root.wifiMenu?.visible)
                return;
            const config = root.barConfig.forScreen(root.wifiMenu.screen?.name ?? "");
            if (config.mode === "off" || !config.modules.wifiMenu)
                root.wifiMenu.visible = false;
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.wifiMenu?.visible && !Quickshell.screens.includes(root.wifiMenu.screen))
                root.wifiMenu.visible = false;
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            if (!Hyprland.focusedMonitor)
                return;
            const bar = outputBars.instances.find(item => item.modelData && Hyprland.monitorFor(item.modelData)?.name === Hyprland.focusedMonitor.name);
            if (bar)
                bar.toggle();
        }
    }

    Variants {
        id: outputBars
        model: root.barConfig.ready ? Quickshell.screens.filter(screen => root.barConfig.forScreen(screen.name).mode !== "off") : []

        BarWindow {
            shared: root
            theme: root.theme
        }
    }
}
