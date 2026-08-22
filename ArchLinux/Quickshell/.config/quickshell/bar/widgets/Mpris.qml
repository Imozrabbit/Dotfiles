import QtQuick

import qs.core as Core

Rectangle {
    id: root

    required property bool active
    required property bool playing
    required property bool paused
    required property bool canTogglePlaying
    required property string app
    required property string title
    required property string artist
    required property Core.Theme theme

    signal togglePlayingRequested

    property bool mprisTooltipVisible: false
    readonly property int maximumWidth: 400
    readonly property string displayText: {
        const title = root.title.trim();
        const artist = root.artist.trim();
        if (title !== "" && artist !== "")
            return title + " — " + artist;
        if (title !== "")
            return title;
        if (artist !== "")
            return artist;
        return root.app.trim() || "Media";
    }

    implicitWidth: root.active ? Math.min(mediaText.implicitWidth + 16, root.maximumWidth) : 0
    implicitHeight: mediaText.implicitHeight + 4

    visible: root.active
    color: "transparent"

    onActiveChanged: {
        if (!active) {
            mprisTooltipDelay.stop();
            root.mprisTooltipVisible = false;
        }
    }

    Text {
        id: mediaText

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        text: root.paused ? " " + root.displayText : "󰝚 " + root.displayText
        textFormat: Text.PlainText
        color: root.paused ? root.theme.whiteMutedColor : root.theme.whiteColor
        elide: Text.ElideRight
        maximumLineCount: 1
        wrapMode: Text.NoWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font {
            family: root.theme.fontFamily
            pixelSize: root.theme.volumeFontSize
            bold: true
        }
    }

    HoverHandler {
        id: mprisHover

        cursorShape: root.canTogglePlaying ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: {
            if (hovered) {
                mprisTooltipDelay.restart();
            } else {
                mprisTooltipDelay.stop();
                root.mprisTooltipVisible = false;
            }
        }
    }

    TapHandler {
        enabled: root.active && root.canTogglePlaying
        onTapped: root.togglePlayingRequested()
    }

    Timer {
        id: mprisTooltipDelay
        interval: 300
        repeat: false
        onTriggered: root.mprisTooltipVisible = root.active && mprisHover.hovered
    }

    SystemStatTooltip {
        visible: root.active && root.mprisTooltipVisible
        anchorItem: root
        heading: root.app !== "" ? root.app : "Media"
        rows: [
            {
                label: "Title",
                value: root.title !== "" ? root.title : "N/A"
            },
            {
                label: "Artist",
                value: root.artist !== "" ? root.artist : "N/A"
            }
        ]
        theme: root.theme
    }
}
