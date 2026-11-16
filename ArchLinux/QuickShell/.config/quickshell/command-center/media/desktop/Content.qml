pragma ComponentBehavior: Bound
import QtQuick
import ".." as Media
import "../../common/Theme.js" as Theme

Item {
    id: root

    property var player: null
    property bool active: false
    property var themeColors: Theme.colors
    property var sourceNames: ({})
    property var spectrumLevels: []
    property point dragOrigin: Qt.point(0, 0)
    signal moveRequested(real x, real y)
    signal actionRequested(var player, string action)
    signal seekRequested(var player, var trackKey, real ratio)
    signal removeRequested
    signal focusRequested

    implicitWidth: 268
    implicitHeight: card.sourceOverhang + card.implicitHeight
    width: implicitWidth
    height: implicitHeight
    enabled: root.active

    function focusCard(): void {
        card.forceActiveFocus(Qt.MouseFocusReason);
    }

    Item {
        anchors.fill: parent
        DragHandler {
            id: drag
            target: null
            enabled: root.active && root.visible
            acceptedButtons: Qt.LeftButton
            // Never take a pointer already grabbed by playback buttons or the seekbar.
            grabPermissions: PointerHandler.ApprovesTakeOverByAnything
            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onActiveChanged: if (active)
                root.dragOrigin = Qt.point(root.x, root.y)
            onActiveTranslationChanged: {
                if (active)
                    root.moveRequested(root.dragOrigin.x + activeTranslation.x, root.dragOrigin.y + activeTranslation.y);
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressedChanged: if (pressed)
            root.focusRequested()
    }

    Media.MediaCard {
        id: card
        objectName: "desktopMediaCard"
        y: sourceOverhang
        width: root.width
        player: root.player
        active: root.active && root.visible
        desktopCopyActive: true
        themeColors: root.themeColors
        sourceNames: root.sourceNames
        spectrumLevels: root.spectrumLevels
        onPreviousRequested: root.actionRequested(player, "previous")
        onPlaybackToggleRequested: root.actionRequested(player, "playPause")
        onNextRequested: root.actionRequested(player, "next")
        onShuffleRequested: root.actionRequested(player, "shuffle")
        onRepeatRequested: root.actionRequested(player, "repeat")
        onSeekRequested: (trackKey, ratio) => root.seekRequested(player, trackKey, ratio)
        onDesktopRequested: root.removeRequested()
    }
}
