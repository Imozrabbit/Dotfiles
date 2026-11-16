pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common/Theme.js" as Theme

PanelWindow { // qmllint disable uncreatable-type
    id: root

    property bool active: false
    property bool captureActive: false
    property ShellScreen targetScreen: null
    property var entries: []
    property var themeColors: Theme.colors
    property real requestedWidth: 350
    property real requestedHeight: 0
    property string feedback: ""
    readonly property ShellScreen displayScreen: root.screen
    readonly property real horizontalInset: Math.min(16, Math.max(0, ((root.displayScreen ? root.displayScreen.width : 350) - 120) / 2))
    readonly property real verticalInset: Math.min(16, Math.max(0, ((root.displayScreen ? root.displayScreen.height : 900) - 56) / 2))
    readonly property real stackMaximumHeight: Math.max(1, (root.displayScreen ? root.displayScreen.height : 900) - 2 * root.verticalInset)
    signal dismissRequested(var entryId, var revision)
    signal actionRequested(var entryId, string action, var revision)
    signal replyRequested(var entryId, string text, var revision)
    signal copyCodeRequested(string code)
    signal copyRequested(var entryId, var revision)
    signal interactionChanged(var entryId, bool hovered, bool focused)
    signal interactionRequested

    screen: root.targetScreen
    // Mapping emits native screenChanged; visibility must use the caller's target instead.
    visible: root.active && (root.entries.length > 0 || root.captureActive) && root.targetScreen !== null
    anchors.top: true
    anchors.right: true
    // Native Margins fields are absent from Quickshell's lint metadata.
    // qmllint disable missing-property
    margins {
        top: root.verticalInset
        right: root.horizontalInset
    }
    // qmllint enable missing-property
    implicitWidth: Math.max(1, Math.min(Math.max(120, root.requestedWidth), (root.displayScreen ? root.displayScreen.width : 350) - 2 * root.horizontalInset))
    implicitHeight: Math.max(1, content.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    focusable: root.visible && root.entries.length > 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-command-center-toast"
    WlrLayershell.keyboardFocus: root.focusable ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: content
    }

    function focusContent(): void {
        content.focusContent();
    }

    Stack {
        id: content
        width: root.width
        entries: root.entries
        themeColors: root.themeColors
        requestedHeight: root.requestedHeight
        maximumHeight: root.stackMaximumHeight
        feedback: root.feedback
        opacity: root.visible ? 1 : 0
        onDismissRequested: (entryId, revision) => root.dismissRequested(entryId, revision)
        onActionRequested: (entryId, action, revision) => root.actionRequested(entryId, action, revision)
        onReplyRequested: (entryId, text, revision) => root.replyRequested(entryId, text, revision)
        onCopyCodeRequested: code => root.copyCodeRequested(code)
        onCopyRequested: (entryId, revision) => root.copyRequested(entryId, revision)
        onInteractionChanged: (entryId, hovered, focused) => root.interactionChanged(entryId, hovered, focused)

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
        HoverHandler {
            onHoveredChanged: if (hovered)
                root.interactionRequested()
        }
    }
}
