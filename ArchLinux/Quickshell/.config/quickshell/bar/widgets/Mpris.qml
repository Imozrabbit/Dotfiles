import QtQuick

import qs.core as Core
import qs.services as Services

Rectangle {
    id: root

    property bool mprisTooltipVisible: false
    property Services.Mpris mprisService: Services.Mpris {}

    //property var state: mprisService.playbackState === MprisPla

    required property Core.Theme theme

    implicitWidth: appName.implicitWidth
    implicitHeight: appName.implicitHeight

    visible: mprisService.active
    color: "transparent"

    Text {
        id: appName
        anchors.centerIn: parent
        text: root.mprisService.canPause ? "  " + root.mprisService.app : "idk"
        color: root.theme.whiteColor
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.volumeFontSize
            bold: true
        }
    }

    HoverHandler {
        id: mprisHover
        onHoveredChanged: {
            if (hovered) {
                mprisTooltipDelay.restart();
            } else {
                mprisTooltipDelay.stop();
                root.mprisTooltipVisible = false;
            }
        }
    }

    Timer {
        id: mprisTooltipDelay
        interval: 300
        repeat: false
        onTriggered: root.mprisTooltipVisible = mprisHover.hovered
    }

    SystemStatTooltip {
        visible: root.mprisTooltipVisible
        anchorItem: root
        heading: root.mprisService.app
        rows: [
            {
                label: "Title",
                value: root.mprisService.title
            },
            {
                label: "Artist",
                value: root.mprisService.artist
            }
        ]
        theme: root.theme
    }
}
