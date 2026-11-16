pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../media/mpris" as Media
import "../media/desktop" as Desktop
import "../media/visualizer" as Visualizer
import "../notifications/history" as History
import "../notifications/toasts" as Toasts
import "../power" as Power
import "../quickactions/network" as Network
import "../quickactions/bluetooth" as BluetoothActions
import "../quickactions/vpn" as Vpn
import "../quickactions/idle" as IdleInhibit
import "../quickactions/localsend" as LocalSend
import "../quickactions/hyprsunset" as Hyprsunset
import "../quickactions/dnd" as Dnd
import "../sliders/audio" as AudioSliders
import "../sliders/brightness" as BrightnessSlider
import "../common/WindowState.js" as WindowState

PanelWindow { // qmllint disable uncreatable-type
    id: root

    required property var settings
    property var notificationController: null
    property var notificationWindows: []
    readonly property var historyController: root.notificationController ?? legacyHistory.item
    readonly property var focusWindows: [root, desktopSurface, toastSurface].concat(root.notificationWindows)
    property bool surfaceVisible: windowState.shown
    readonly property ShellScreen displayScreen: root.screen
    readonly property bool mediaSectionEnabled: root.settings.sections.some(section => section.id === "media" && section.enabled)
    readonly property bool panelMediaActive: windowState.shown && root.surfaceVisible && panel.mediaVisible

    visible: root.surfaceVisible
    anchors.right: true
    implicitWidth: Math.min(root.settings.panel.width, root.displayScreen ? root.displayScreen.width : 300)
    implicitHeight: Math.min(root.settings.panel.height, root.displayScreen ? root.displayScreen.height : 900)
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: windowState.shown
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "quickshell-command-center"
    WlrLayershell.keyboardFocus: windowState.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: panel
    }

    PersistentProperties {
        id: windowState
        reloadableId: "command-center-window"
        property bool shown: false
        property string screenName: ""
        onLoaded: root.restoreScreen()
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: root.focusWindows
    }

    Timer {
        id: hideTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (!windowState.shown)
                root.surfaceVisible = false;
        }
    }

    function focusedScreenName() {
        for (const candidate of Quickshell.screens) {
            const monitor = Hyprland.monitorFor(candidate);
            if (monitor && monitor.focused)
                return candidate.name;
        }
        return Hyprland.focusedMonitor?.name || (root.displayScreen ? root.displayScreen.name : "");
    }

    function restoreScreen() {
        const target = Quickshell.screens.find(candidate => candidate.name === windowState.screenName);
        if (target)
            root.screen = target;
    }

    function closeWindow(): bool {
        if (!windowState.shown)
            return false;
        root.toggleWindow();
        return true;
    }

    function toggleWindow(): bool {
        const next = WindowState.toggleState(windowState.shown, root.displayScreen ? root.displayScreen.name : "", root.focusedScreenName());
        windowState.screenName = next.screenName;
        if (next.shown) {
            hideTimer.stop();
            root.restoreScreen();
            root.surfaceVisible = true;
        } else {
            focusGrab.active = false;
            hideTimer.restart();
        }
        windowState.shown = next.shown;
        return next.shown;
    }

    function executeAction(action: string): void {
        if (powerCommands.busy || networkCommands.busy)
            return;
        if (action.startsWith("quick:")) {
            const entry = root.settings.quickActions[Number(action.slice(6))];
            if (!entry || entry.enabled === false)
                return;
            if (entry && entry.id === "network")
                networkCommands.toggle();
            else if (entry && entry.id === "bluetooth")
                bluetoothCommands.toggle();
            else if (entry && entry.id === "vpn")
                vpnCommands.toggle();
            else if (entry && entry.id === "idle-inhibit")
                idleInhibitCommands.toggle();
            else if (entry && entry.id === "localsend")
                localsendCommands.toggle();
            else if (entry && entry.id === "hyprsunset")
                hyprsunsetCommands.toggle();
            else if (entry && entry.id === "dnd")
                dndCommands.toggle();
        } else {
            powerCommands.execute(action);
        }
    }

    function actionOptions(id: string): var {
        return root.settings.quickActions.find(action => action.id === id && action.enabled !== false) ?? null;
    }

    function sliderEnabled(type: string): bool {
        return root.settings.sections.some(section => section.id === "sliders" && section.enabled) && root.settings.sliders.some(slider => slider.type === type && slider.enabled !== false);
    }

    function toggleDesktopCopy(player: var): bool {
        const screen = Quickshell.screens.find(candidate => candidate.name === root.focusedScreenName()) ?? Quickshell.screens.find(candidate => candidate === root.displayScreen) ?? Quickshell.screens[0] ?? null;
        return desktopCopy.toggle(player, screen);
    }

    function focusSurface(surface: var): void {
        // A target-only commit moves keyboard focus even when the shared grab is already active.
        focusGrab.windows = [surface];
        focusGrab.active = true;
        focusGrab.windows = root.focusWindows;
    }

    function focusNotificationSurface(surface: var): void {
        if (powerCommands.busy || networkCommands.busy)
            return;
        surface.focusContent();
        root.focusSurface(surface);
    }

    AudioSliders.Service {
        id: outputVolume
        enabled: root.sliderEnabled("volume")
        node: Pipewire.defaultAudioSink
    }

    AudioSliders.Service {
        id: inputVolume
        enabled: root.sliderEnabled("microphone")
        node: Pipewire.defaultAudioSource
    }

    BrightnessSlider.Controller {
        id: backlight
        enabled: root.sliderEnabled("brightness")
        outputs: Quickshell.screens.map(screen => screen.name)
        panelOpen: windowState.shown
    }

    Media.Service {
        id: mediaControl
        enabled: root.mediaSectionEnabled || desktopCopy.visible
        activePlayers: [root.panelMediaActive ? panel.currentMediaPlayer : null, desktopCopy.visible ? desktopCopy.player : null]
    }

    Desktop.Controller {
        id: desktopCopy
        players: mediaControl.players
        screens: Quickshell.screens
        requestedWidth: panel.mediaCardWidth
        cardHeight: desktopSurface.cardHeight
    }

    Desktop.Surface {
        id: desktopSurface
        controller: desktopCopy
        themeColors: panel.themeColors
        sourceNames: root.settings.media.sourceNames
        spectrumLevels: cavaSpectrum.levels
        onActionRequested: (player, action) => mediaControl.perform(player, action)
        onSeekRequested: (player, trackKey, ratio) => mediaControl.seek(player, trackKey, ratio)
        onInteractionRequested: {
            if (powerCommands.busy || networkCommands.busy)
                return;
            desktopSurface.focusContent();
            root.focusSurface(desktopSurface);
        }
    }

    Visualizer.Service {
        id: cavaSpectrum
        enabled: root.settings.media.cavaEnabled && ((root.panelMediaActive && !!panel.currentMediaPlayer) || desktopCopy.visible) && !!Pipewire.defaultAudioSink
        outputName: Pipewire.defaultAudioSink?.name ?? ""
    }

    Power.Service {
        id: powerCommands
        actions: root.settings.powerActions
        onBusyChanged: {
            if (powerCommands.busy)
                focusGrab.active = false;
        }
    }

    Network.Service {
        id: networkCommands
        enabled: root.settings.quickActions.some(action => action.id === "network" && action.enabled !== false)
        observing: networkCommands.enabled || vpnCommands.enabled
        onConnectionsChanged: vpnCommands.refresh()
        onBusyChanged: {
            if (networkCommands.busy)
                focusGrab.active = false;
        }
    }

    BluetoothActions.Service {
        id: bluetoothCommands
        enabled: root.settings.quickActions.some(action => action.id === "bluetooth" && action.enabled !== false)
    }

    Vpn.Service {
        id: vpnCommands
        enabled: root.actionOptions("vpn") !== null
        defaultProfile: root.actionOptions("vpn")?.defaultProfile ?? ""
        profileNames: root.actionOptions("vpn")?.profileNames ?? ({})
        monitorRunning: networkCommands.monitorRunning
    }

    IdleInhibit.Service {
        id: idleInhibitCommands
        enabled: root.settings.quickActions.some(action => action.id === "idle-inhibit" && action.enabled !== false)
    }

    LocalSend.Service {
        id: localsendCommands
        enabled: root.actionOptions("localsend") !== null
        panelOpen: windowState.shown
        scriptPath: root.actionOptions("localsend")?.scriptPath ?? ""
    }

    Hyprsunset.Service {
        id: hyprsunsetCommands
        enabled: root.settings.sections.some(section => section.id === "quickActions" && section.enabled) && root.actionOptions("hyprsunset") !== null
        panelOpen: windowState.shown
        temperature: root.actionOptions("hyprsunset")?.temperature ?? 4500
    }

    Dnd.Service {
        id: dndCommands
        enabled: root.settings.quickActions.some(action => action.id === "dnd" && action.enabled !== false)
        controller: root.notificationController
    }

    Loader {
        id: legacyHistory
        active: root.notificationController === null
        sourceComponent: History.Service {
            id: notificationHistory
        }
    }

    Toasts.Preview {
        id: toastPreview
        screens: Quickshell.screens
        focusedScreenName: root.focusedScreenName()
    }

    Toasts.Surface {
        id: toastSurface
        active: root.notificationController === null && toastPreview.visible
        entries: toastPreview.entries
        targetScreen: toastPreview.screen
        requestedWidth: root.settings.toast.width
        requestedHeight: root.settings.toast.height
        themeColors: panel.themeColors
        feedback: toastPreview.feedback
        onDismissRequested: entryId => toastPreview.dismiss(entryId)
        onActionRequested: toastPreview.acknowledge("Sample action selected; nothing sent to an application.")
        onReplyRequested: toastPreview.acknowledge("Sample reply entered; nothing sent to an application.")
        onCopyCodeRequested: toastPreview.acknowledge("Sample Copy selected; clipboard unchanged.")
        onInteractionRequested: {
            if (powerCommands.busy || networkCommands.busy)
                return;
            toastSurface.focusContent();
            root.focusSurface(toastSurface);
        }
    }

    PanelContent {
        id: panel
        width: root.width
        height: root.height
        x: windowState.shown ? 0 : width
        backgroundColor: root.settings.background.color
        backgroundOpacity: root.settings.background.opacity
        colors: root.settings.colors
        leftPadding: root.settings.padding.left
        rightPadding: root.settings.padding.right
        quickActions: root.settings.quickActions
        network: networkCommands
        bluetooth: bluetoothCommands
        vpn: vpnCommands
        idleInhibit: idleInhibitCommands
        localsend: localsendCommands
        hyprsunset: hyprsunsetCommands
        dnd: dndCommands
        powerActions: root.settings.powerActions
        powerActionsBusy: powerCommands.busy || networkCommands.busy
        sliders: root.settings.sliders
        volumeControl: outputVolume
        microphoneControl: inputVolume
        brightnessControl: backlight
        sections: root.settings.sections
        entries: root.historyController?.entries ?? []
        historyBusy: root.historyController?.busy ?? false
        historyError: root.historyController?.lastError || ""
        toastPreviewAvailable: root.notificationController === null
        toastPreviewVisible: toastPreview.visible
        mediaPlayers: mediaControl.players
        mediaActive: root.panelMediaActive
        desktopCopyActive: desktopCopy.visible
        mediaSourceNames: root.settings.media.sourceNames
        spectrumLevels: cavaSpectrum.levels
        onActionRequested: action => root.executeAction(action)
        onDismissRequested: (entryId, revision) => {
            if (root.notificationController)
                root.notificationController.clear(entryId, revision);
            else
                (legacyHistory.item as History.Service)?.clear(entryId);
        }
        onDismissGroupRequested: appName => root.historyController?.clearGroup(appName)
        onClearAllRequested: root.historyController?.clearAll()
        onNotificationActionRequested: (entryId, action, revision) => root.notificationController?.invoke(entryId, revision, action)
        onNotificationReplyRequested: (entryId, text, revision) => root.notificationController?.reply(entryId, revision, text)
        onToastPreviewRequested: toastPreview.toggle()
        onMediaRequested: (player, action) => {
            if (action === "toDesktop")
                root.toggleDesktopCopy(player);
            else
                mediaControl.perform(player, action);
        }
        onMediaSeekRequested: (player, trackKey, ratio) => mediaControl.seek(player, trackKey, ratio)

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (!hovered || !windowState.shown || powerCommands.busy || networkCommands.busy)
                    return;
                panel.forceActiveFocus(Qt.MouseFocusReason);
                root.focusSurface(root);
            }
        }
    }
}
