import QtQuick

import qs.core as Core

Rectangle {
    id: root

    required property bool active
    required property bool paused
    required property bool canTogglePlaying
    required property string app
    required property string title
    required property string artist
    required property Core.Theme theme
    required property real availableWidth

    signal togglePlayingRequested

    property bool mprisTooltipVisible: false
    readonly property int maximumWidth: 400
    property real scrollOffset: 0
    readonly property real textWidth: mediaText.implicitWidth
    readonly property bool scrolling: root.visible && textViewport.width > 0 && root.textWidth > textViewport.width
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

    implicitWidth: root.active ? Math.max(0, Math.min(root.textWidth + 16, root.maximumWidth, root.availableWidth)) : 0
    implicitHeight: mediaText.implicitHeight + 4

    visible: root.active && width >= root.theme.volumeFontSize + 16
    color: "transparent"

    onVisibleChanged: {
        if (!visible) {
            mprisTooltipDelay.stop();
            root.mprisTooltipVisible = false;
        }
    }

    onActiveChanged: {
        if (!active) {
            mprisTooltipDelay.stop();
            root.mprisTooltipVisible = false;
        }
    }

    function restartScroll() {
        scrollAnimation.stop();
        root.scrollOffset = 0;
        if (root.scrolling)
            scrollAnimation.start();
    }

    onScrollingChanged: Qt.callLater(root.restartScroll)
    onWidthChanged: Qt.callLater(root.restartScroll)
    onDisplayTextChanged: Qt.callLater(root.restartScroll)

    NumberAnimation {
        id: scrollAnimation
        target: root
        property: "scrollOffset"
        from: 0
        to: root.textWidth + 32
        duration: Math.max(1, Math.round((root.textWidth + 32) * 1000 / 30))
        loops: Animation.Infinite
    }

    Item {
        id: textViewport
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true

        Row {
            x: root.scrolling ? -root.scrollOffset : Math.max(0, (textViewport.width - root.textWidth) / 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 32

            Text {
                id: mediaText
                text: root.paused ? " " + root.displayText : "󰝚 " + root.displayText
                textFormat: Text.PlainText
                color: root.paused ? root.theme.whiteMutedColor : root.theme.whiteColor
                wrapMode: Text.NoWrap
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.volumeFontSize
                    bold: true
                }
            }

            Text {
                visible: root.scrolling
                text: mediaText.text
                textFormat: Text.PlainText
                color: mediaText.color
                font: mediaText.font
                wrapMode: Text.NoWrap
            }
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
