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

    screen: root.modelData
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.shown ? 35 : 2
    color: "transparent"
    WlrLayershell.exclusiveZone: root.mode === "always" ? 35 : -1

    onModeChanged: {
        hideTimer.stop();
        root.hoverRevealed = false;
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

    Item {
        anchors.fill: parent
        visible: root.shown
        Widgets.Mpris {
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
