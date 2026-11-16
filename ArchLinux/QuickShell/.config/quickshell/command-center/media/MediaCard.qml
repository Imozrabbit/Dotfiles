pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../components"
import "visualizer" as Visualizer
import "../common/Theme.js" as Theme

Rectangle {
    id: root

    property var player: null
    property var themeColors: Theme.colors
    property var sourceNames: ({})
    property var spectrumLevels: []
    property bool active: true
    property bool desktopCopyActive: false
    readonly property bool browserSource: root.player?.isBrowser === true
    readonly property bool seeking: progress.seeking
    signal previousRequested
    signal playbackToggleRequested
    signal nextRequested
    signal shuffleRequested
    signal repeatRequested
    signal desktopRequested
    signal seekRequested(var trackKey, real ratio)

    readonly property real metadataX: cover.x + cover.width + 12
    readonly property real metadataWidth: Math.max(0, width - metadataX - 12)
    readonly property real sourceOverhang: sourceBackground.height / 2
    readonly property real sourceCenterY: 2

    implicitHeight: visible ? controls.y + controls.implicitHeight + 12 : 0
    height: implicitHeight
    radius: Theme.radius
    color: root.themeColors.mediaSurface
    border.color: root.themeColors.sectionBorder
    border.width: border.color.a > 0 ? 1 : 0

    function metadata(value: var, fallback: string): string {
        return typeof value === "string" && value.trim() !== "" ? value : fallback;
    }

    component MediaButton: ActionTile {
        id: mediaButton
        property bool active: false
        readonly property color baseColor: active ? root.themeColors.tileActive : root.themeColors.text
        readonly property color highlightedColor: {
            const brighter = Qt.lighter(mediaButton.baseColor, 1.15);
            return brighter.toString() === mediaButton.baseColor.toString() ? Qt.darker(mediaButton.baseColor, 1.15) : brighter;
        }
        themeColors: root.themeColors
        implicitWidth: 32
        implicitHeight: 40
        background: null
        iconColor: !enabled ? mediaButton.baseColor : down ? Qt.darker(mediaButton.baseColor, 1.25) : hovered || visualFocus ? mediaButton.highlightedColor : mediaButton.baseColor
    }

    Visualizer.Spectrum {
        objectName: "mediaSpectrum"
        anchors.fill: parent
        radius: root.radius
        levels: root.active && root.player ? root.spectrumLevels : []
        themeColors: root.themeColors
    }

    Image {
        id: cover
        objectName: "mediaCover"
        x: 12
        y: (root.height - height) / 2
        width: Math.min(72, Math.max(0, (root.width - 24) * 0.3))
        height: width
        source: typeof root.player?.artUrl === "string" ? root.player.artUrl : ""
        asynchronous: true
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }

    Rectangle {
        objectName: "mediaArtworkFallback"
        x: cover.x
        y: cover.y
        width: cover.width
        height: cover.height
        radius: 8
        color: root.themeColors.gridTile
        visible: cover.status !== Image.Ready

        Text {
            anchors.fill: parent
            text: "󰝚"
            font.family: Theme.iconFont
            font.pixelSize: 24
            color: root.themeColors.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Text {
        objectName: "mediaTitle"
        x: root.metadataX
        y: root.browserSource ? 30 : 16
        width: Math.max(0, Math.min(root.metadataWidth, desktopToggle.x - x - 4))
        height: 18
        text: root.player ? root.metadata(root.player.title, "Unknown track") : "Nothing playing"
        font.family: Theme.textFont
        font.pixelSize: 14
        font.bold: true
        color: root.themeColors.text
        elide: Text.ElideRight
        textFormat: Text.PlainText
        clip: true
    }

    Text {
        objectName: "mediaArtist"
        x: root.metadataX
        y: root.browserSource ? 54 : 40
        width: root.metadataWidth
        height: 14
        text: root.player ? root.metadata(root.player.artist, "Unknown artist") : ""
        font.family: Theme.textFont
        font.pixelSize: 11
        color: root.themeColors.muted
        elide: Text.ElideRight
        textFormat: Text.PlainText
        clip: true
    }

    Item {
        x: (root.width - width) / 2
        y: root.sourceCenterY - root.sourceOverhang
        width: sourceBackground.width
        height: Math.max(0, -y)
        // The card already paints the covered portion; clipping avoids doubling its alpha.
        clip: true

        Rectangle {
            id: sourceBackground
            objectName: "mediaSourceNotch"
            width: Math.min(sourceLabel.width + 16, Math.max(0, root.width - 24))
            height: sourceLabel.height + 6
            radius: 8
            color: root.color
            antialiasing: true
        }
    }

    Text {
        id: sourceLabel
        objectName: "mediaSource"
        x: (root.width - width) / 2
        y: root.sourceCenterY - height / 2
        width: Math.min(implicitWidth, Math.max(0, root.width - 2 * (desktopToggle.width + 8)))
        height: 14
        text: {
            const original = root.player ? root.metadata(root.player.name, "Player") : "Media";
            const id = root.player?.desktopEntry;
            return typeof id === "string" && root.sourceNames && Object.prototype.hasOwnProperty.call(root.sourceNames, id) ? root.metadata(root.sourceNames[id], original) : original;
        }
        color: root.themeColors.text
        font.family: Theme.textFont
        font.pixelSize: 10
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        clip: true
    }

    MediaButton {
        id: desktopToggle
        objectName: "mediaToDesktop"
        x: Math.max(0, root.width - width)
        y: 0
        implicitHeight: 32
        glyph: root.desktopCopyActive ? "󱂬" : "󰏌"
        tooltip: root.desktopCopyActive ? "Remove desktop copy" : "To desktop"
        active: root.desktopCopyActive
        enabled: root.active && (!!root.player || root.desktopCopyActive)
        Accessible.checkable: true
        Accessible.checked: root.desktopCopyActive
        Accessible.description: root.desktopCopyActive ? "Remove only desktop copy; original stays in panel" : "Create live copy on focused monitor"
        onClicked: root.desktopRequested()
    }

    MediaProgress {
        id: progress
        objectName: "mediaProgress"
        visible: !root.browserSource
        x: root.metadataX
        y: 58
        width: root.metadataWidth
        height: implicitHeight
        progress: root.player?.progress ?? 0
        playing: root.active && root.player?.playing === true
        seekable: root.active && root.player?.canSeek === true
        seekPlayer: root.player
        trackKey: root.player?.trackKey ?? null
        onSeekRequested: ratio => root.seekRequested(root.player?.trackKey, ratio)
        waveColor: root.themeColors.tileActive
        trackColor: root.themeColors.sliderTrack
    }

    Item {
        id: controls
        objectName: "mediaControls"
        width: Math.min(184, root.metadataWidth)
        x: root.metadataX + (root.metadataWidth - width) / 2
        y: 88
        implicitHeight: positions[4].y + 40
        height: implicitHeight
        readonly property var positions: {
            const widths = [32, 32, 40, 32, 32];
            const rows = [[]];
            let used = 0;
            for (let index = 0; index < widths.length; ++index) {
                if (used && used + 4 + widths[index] > width) {
                    rows.push([]);
                    used = 0;
                }
                rows[rows.length - 1].push(index);
                used += (used ? 4 : 0) + widths[index];
            }
            const result = [];
            rows.forEach((row, rowIndex) => {
                const total = row.reduce((sum, index) => sum + widths[index], 0) + (row.length - 1) * 4;
                let next = Math.max(0, (width - total) / 2);
                row.forEach(index => {
                    result[index] = {
                        x: next,
                        y: rowIndex * 44
                    };
                    next += widths[index] + 4;
                });
            });
            return result;
        }

        MediaButton {
            objectName: "mediaShuffle"
            x: controls.positions[0].x
            y: controls.positions[0].y
            glyph: "󰒝"
            tooltip: "Shuffle"
            enabled: root.active && root.player?.canShuffle === true
            active: root.player?.shuffle === true
            Accessible.checkable: true
            Accessible.checked: root.player?.shuffle === true
            onClicked: root.shuffleRequested()
        }
        MediaButton {
            objectName: "mediaPrevious"
            x: controls.positions[1].x
            y: controls.positions[1].y
            glyph: "󰒮"
            tooltip: "Previous track"
            enabled: root.active && root.player?.canGoPrevious === true
            onClicked: root.previousRequested()
        }
        ActionTile {
            objectName: "mediaPlayback"
            x: controls.positions[2].x
            y: controls.positions[2].y
            themeColors: root.themeColors
            implicitWidth: 40
            implicitHeight: 40
            glyph: root.player?.playing === true ? "󰏤" : "󰐊"
            tooltip: "Play / pause"
            enabled: root.active && root.player?.canTogglePlaying === true
            Accessible.name: root.player?.playing === true ? "Pause" : "Play"
            fillColor: root.themeColors.tileActive
            hoverColor: Qt.lighter(root.themeColors.tileActive, 1.15)
            iconColor: root.themeColors.onActive
            onClicked: root.playbackToggleRequested()
        }
        MediaButton {
            objectName: "mediaNext"
            x: controls.positions[3].x
            y: controls.positions[3].y
            glyph: "󰒭"
            tooltip: "Next track"
            enabled: root.active && root.player?.canGoNext === true
            onClicked: root.nextRequested()
        }
        MediaButton {
            objectName: "mediaRepeat"
            x: controls.positions[4].x
            y: controls.positions[4].y
            glyph: root.player?.repeatMode === 2 ? "󰑘" : "󰑖"
            tooltip: "Repeat"
            enabled: root.active && root.player?.canRepeat === true
            active: root.player?.repeatMode === 1 || root.player?.repeatMode === 2
            Accessible.description: "Repeat " + (root.player?.repeatMode === 2 ? "one track" : root.player?.repeatMode === 1 ? "playlist" : "off")
            onClicked: root.repeatRequested()
        }
    }
}
