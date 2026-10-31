pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    required property Item anchorItem
    property bool visible: false
    property bool below: false
    property int implicitWidth: 1
    property int implicitHeight: 1
    default property alias content: tooltipWindow.data

    readonly property PanelWindow sourceWindow: root.anchorItem?.QsWindow.window ?? null
    readonly property ShellScreen sourceScreen: root.sourceWindow?.screen ?? null
    property rect anchorRect: Qt.rect(0, 0, 0, 0)

    function updateAnchorRect() {
        root.anchorRect = root.visible && root.anchorItem && root.sourceWindow ? root.sourceWindow.contentItem.mapFromItem(root.anchorItem, 0, 0, root.anchorItem.width, root.anchorItem.height) : Qt.rect(0, 0, 0, 0);
    }

    onVisibleChanged: root.updateAnchorRect()
    onAnchorItemChanged: root.updateAnchorRect()
    onSourceWindowChanged: root.updateAnchorRect()

    readonly property TransformWatcher positionWatcher: TransformWatcher {
        a: root.visible ? root.sourceWindow?.contentItem ?? null : null
        b: root.visible ? root.anchorItem : null
        onTransformChanged: root.updateAnchorRect()
    }
    // TransformWatcher misses explicit Translate transforms; follow existing source frames, too.
    readonly property Connections sourceFrames: Connections {
        target: root.visible ? root.anchorItem?.Window.window ?? null : null
        function onAfterAnimating() {
            root.updateAnchorRect();
        }
    }

    readonly property PanelWindow window: PanelWindow { // qmllint disable uncreatable-type
        id: tooltipWindow

        visible: root.visible && root.anchorItem !== null && root.anchorItem.visible && root.sourceWindow !== null && root.sourceWindow.visible && root.sourceWindow.backingWindowVisible && Quickshell.screens.includes(root.sourceScreen)
        screen: root.sourceScreen
        color: "transparent"
        focusable: false
        mask: Region {}
        exclusionMode: ExclusionMode.Ignore
        anchors.left: true
        anchors.top: true
        WlrLayershell.namespace: "quickshell-bar-tooltip"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        implicitWidth: Math.max(1, Math.min(root.implicitWidth, root.sourceScreen?.width ?? root.implicitWidth))
        implicitHeight: Math.max(1, Math.min(root.implicitHeight, root.sourceScreen?.height ?? root.implicitHeight))
        contentItem.clip: true

        // Both bar owners span their output and attach to its top or bottom edge.
        // Quickshell's generated lint metadata omits the Margins gadget's fields.
        // qmllint disable missing-property
        margins.left: {
            const source = root.sourceWindow;
            if (!source || !root.sourceScreen)
                return 0;
            const x = source.margins.left + root.anchorRect.x + root.anchorRect.width / 2 - tooltipWindow.implicitWidth / 2;
            return Math.round(Math.max(0, Math.min(root.sourceScreen.width - tooltipWindow.implicitWidth, x)));
        }
        margins.top: {
            const source = root.sourceWindow;
            if (!source || !root.sourceScreen)
                return 0;
            const panelY = source.anchors.top ? source.margins.top : root.sourceScreen.height - source.margins.bottom - source.height;
            const y = panelY + root.anchorRect.y + (root.below ? root.anchorRect.height + 8 : -8 - tooltipWindow.implicitHeight);
            return Math.round(Math.max(0, Math.min(root.sourceScreen.height - tooltipWindow.implicitHeight, y)));
        }
        // qmllint enable missing-property
    }
}
