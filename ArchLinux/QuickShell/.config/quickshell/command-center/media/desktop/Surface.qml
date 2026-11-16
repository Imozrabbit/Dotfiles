pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common/Theme.js" as Theme

PanelWindow { // qmllint disable uncreatable-type
    id: root

    required property Controller controller
    property var themeColors: Theme.colors
    property var sourceNames: ({})
    property var spectrumLevels: []
    readonly property real cardHeight: content.implicitHeight
    signal actionRequested(var player, string action)
    signal seekRequested(var player, var trackKey, real ratio)
    signal interactionRequested

    visible: root.controller.visible
    screen: root.controller.screen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    focusable: visible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-command-center-media-copy"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: contentMask

    Region {
        id: contentMask
        item: content
    }

    function focusContent(): void {
        content.focusCard();
    }

    Content {
        id: content
        x: root.controller.x
        y: root.controller.y
        width: root.controller.width
        active: root.controller.visible
        player: root.controller.player
        themeColors: root.themeColors
        sourceNames: root.sourceNames
        spectrumLevels: root.spectrumLevels
        onMoveRequested: (x, y) => root.controller.moveTo(x, y)
        onActionRequested: (player, action) => root.actionRequested(player, action)
        onSeekRequested: (player, trackKey, ratio) => root.seekRequested(player, trackKey, ratio)
        onRemoveRequested: root.controller.remove()
        onFocusRequested: root.interactionRequested()
    }
}
