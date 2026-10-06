import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core as Core
import qs.widgets as Widgets

PanelWindow { // qmllint disable uncreatable-type
    id: root

    required property ShellScreen modelData
    required property var shared
    required property Core.Theme theme
    readonly property string mode: root.shared.barConfig.forScreen(root.modelData.name).topMediaMode
    readonly property var service: root.shared.mprisService
    property bool hoverRevealed: false
    readonly property bool shown: root.mode === "always" || root.hoverRevealed
    property bool windowExpanded: root.shown

    screen: root.modelData
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.windowExpanded ? 35 : 2
    color: "transparent"
    WlrLayershell.exclusiveZone: root.mode === "always" ? 35 : -1

    onModeChanged: {
        hideTimer.stop();
        root.hoverRevealed = false;
        collapseTimer.stop();
        root.windowExpanded = root.mode === "always";
    }

    onShownChanged: {
        if (root.shown) {
            collapseTimer.stop();
            root.windowExpanded = true;
        } else {
            collapseTimer.restart();
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop();
                root.hoverRevealed = root.mode === "hover";
            } else if (root.mode === "hover") {
                hideTimer.restart();
            }
        }
    }
    Timer {
        id: hideTimer
        interval: 80
        onTriggered: root.hoverRevealed = false
    }
    Timer {
        id: collapseTimer
        interval: 20
        onTriggered: {
            if (!root.shown)
                root.windowExpanded = false;
        }
    }

    Item {
        anchors.fill: parent
        visible: root.windowExpanded
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            enabled: root.mode === "hover"
            NumberAnimation {
                duration: root.shown ? 10 : 20
                easing.type: Easing.Linear
            }
        }
        transform: Translate {
            y: root.shown ? 0 : -4
            Behavior on y {
                enabled: root.mode === "hover"
                NumberAnimation {
                    duration: root.shown ? 10 : 20
                    easing.type: Easing.Linear
                }
            }
        }
        Widgets.Mpris {
            topPanel: true
            anchors.centerIn: parent
            availableWidth: root.width * 0.4
            active: root.service?.active ?? false
            paused: root.service?.paused ?? false
            canTogglePlaying: root.service?.canTogglePlaying ?? false
            app: root.service?.app ?? ""
            title: root.service?.title ?? ""
            artist: root.service?.artist ?? ""
            theme: root.theme
            onTogglePlayingRequested: root.service?.togglePlaying()
        }
    }
}
