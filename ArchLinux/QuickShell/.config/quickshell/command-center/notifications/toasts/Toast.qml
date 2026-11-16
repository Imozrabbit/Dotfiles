pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components"
import ".." as Notifications
import "../../common/Theme.js" as Theme

FocusScope {
    id: root

    property var entry: ({})
    property var themeColors: Theme.colors
    property real requestedHeight: 0
    property real maximumHeight: 900
    readonly property string imageSource: root.localImage(root.entry.image)
    readonly property bool imageExpected: root.entry.imageExpected === true || !!root.entry.image
    readonly property bool hovered: hover.hovered
    readonly property bool interactiveFocus: root.activeFocus
    readonly property bool criticalAnimationRunning: criticalBlink.running
    signal dismissRequested(var entryId, var revision)
    signal actionRequested(var entryId, string action, var revision)
    signal replyRequested(var entryId, string text, var revision)
    signal copyCodeRequested(string code)
    signal copyRequested(var entryId, var revision)
    signal interactionChanged(var entryId, bool hovered, bool focused)
    onHoveredChanged: root.interactionChanged(root.entry.id, root.hovered, root.interactiveFocus)
    onInteractiveFocusChanged: root.interactionChanged(root.entry.id, root.hovered, root.interactiveFocus)
    Component.onDestruction: root.interactionChanged(root.entry.id, false, false)

    implicitWidth: 350
    implicitHeight: content.implicitHeight + 24
    height: Math.max(0, Math.min(root.maximumHeight, root.requestedHeight > 0 ? Math.max(56, root.requestedHeight) : implicitHeight))

    function localImage(source): string {
        if (typeof source !== "string")
            return "";
        return (source.startsWith("/") && !source.startsWith("//")) || source.startsWith("file:///") || source.startsWith("qrc:/") || source.startsWith("image://") ? source : "";
    }

    function revealFocus(): void {
        const item = root.Window.window?.activeFocusItem;
        if (!root.activeFocus || !item || item === root)
            return;
        const point = item.mapToItem(scroll.contentItem, 0, 0);
        const maximum = Math.max(0, scroll.contentHeight - scroll.height);
        if (point.y < scroll.contentY)
            scroll.contentY = Math.max(0, Math.min(maximum, point.y));
        else if (point.y + item.height > scroll.contentY + scroll.height)
            scroll.contentY = Math.max(0, Math.min(maximum, point.y + item.height - scroll.height));
    }

    Rectangle {
        objectName: "toastBackground"
        anchors.fill: parent
        radius: 10
        color: root.themeColors.toastBackground
    }

    Rectangle {
        id: criticalBorder
        anchors.fill: parent
        radius: 10
        color: "transparent"
        visible: root.entry.critical === true
        border.width: 2
        border.color: "#ff5555"

        SequentialAnimation {
            id: criticalBlink
            running: root.entry.critical === true && root.visible && (!root.Window.window || root.Window.window.visible)
            loops: Animation.Infinite
            NumberAnimation {
                target: criticalBorder
                property: "opacity"
                from: 1
                to: 0.25
                duration: 900
            }
            NumberAnimation {
                target: criticalBorder
                property: "opacity"
                from: 0.25
                to: 1
                duration: 900
            }
        }
    }

    Flickable {
        id: scroll
        objectName: "toastContentScroll"
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: width
        contentHeight: content.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onHeightChanged: Qt.callLater(root.revealFocus)
        ScrollBar.vertical: ScrollBar {
            width: 4
        }

        Column {
            id: content
            width: scroll.width
            spacing: 8
            onPositioningComplete: Qt.callLater(root.revealFocus)

            RowLayout {
                width: parent.width
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 6
                    color: "#4e4e4e"
                    Text {
                        anchors.centerIn: parent
                        text: (root.entry.appName || "Notification").charAt(0).toUpperCase()
                        color: "#c3c3c5"
                        font.family: Theme.iconFont
                        font.pixelSize: 16
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.entry.appName || "Notification"
                    color: "#c3c3c5"
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    text: root.entry.time || ""
                    color: "#8e8fe0"
                    font.family: Theme.iconFont
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                }
                ActionTile {
                    objectName: "toastClose"
                    implicitWidth: 28
                    implicitHeight: 28
                    glyph: "×"
                    tooltip: "Close notification"
                    themeColors: root.themeColors
                    fillColor: root.themeColors.toastButtonBackground
                    hoverColor: Qt.lighter(root.themeColors.toastButtonBackground, 1.5)
                    enabled: root.entry.dismissEnabled !== false
                    onClicked: root.dismissRequested(root.entry.id, root.entry.revision ?? 0)
                }
            }

            Text {
                width: parent.width
                text: root.entry.summary || ""
                visible: text !== ""
                color: "#c3c3c5"
                font.family: Theme.iconFont
                font.pixelSize: 15
                font.bold: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            Text {
                objectName: "toastBody"
                width: parent.width
                text: root.entry.body || ""
                visible: text !== ""
                color: "#c3c3c5"
                font.family: Theme.iconFont
                font.pixelSize: 12
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Column {
                width: parent.width
                topPadding: 8
                visible: root.imageExpected

                Item {
                    width: parent.width
                    height: preview.status === Image.Ready ? 150 : 40
                    Image {
                        id: preview
                        objectName: "toastImage"
                        anchors.fill: parent
                        source: root.imageSource
                        sourceSize: Qt.size(300, 150)
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                    Text {
                        objectName: "toastImageUnavailable"
                        anchors.centerIn: parent
                        visible: preview.status !== Image.Ready
                        text: "Unavailable"
                        color: "#8e8fe0"
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }
            }

            Grid {
                id: actionGrid
                width: parent.width
                columns: 3
                spacing: 6
                topPadding: 8
                visible: (root.entry.actions || []).length > 0 || !!root.entry.code

                Repeater {
                    model: root.entry.actions || []
                    delegate: Notifications.ActionButton {
                        required property var modelData
                        fillColor: root.themeColors.toastButtonBackground
                        objectName: "toastAction-" + modelData.id
                        text: modelData.text
                        width: Math.max(0, (actionGrid.width - 2 * actionGrid.spacing) / 3)
                        onClicked: root.actionRequested(root.entry.id, modelData.id, root.entry.revision ?? 0)
                    }
                }
                Notifications.ActionButton {
                    objectName: "toastCopyCode"
                    fillColor: root.themeColors.toastButtonBackground
                    visible: !!root.entry.code
                    text: "Copy " + (root.entry.code || "")
                    width: Math.max(0, (actionGrid.width - 2 * actionGrid.spacing) / 3)
                    onClicked: {
                        root.copyRequested(root.entry.id, root.entry.revision ?? 0);
                        root.copyCodeRequested(root.entry.code);
                    }
                }
            }

            RowLayout {
                width: parent.width
                visible: root.entry.hasInlineReply === true
                spacing: 6

                TextField {
                    id: reply
                    objectName: "toastReplyInput"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    placeholderText: root.entry.inlineReplyPlaceholder || "Reply"
                    Accessible.name: placeholderText
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                    color: "#c3c3c5"
                    placeholderTextColor: "#8e8fe0"
                    selectByMouse: true
                    background: Rectangle {
                        radius: 6
                        color: "#40000000"
                        border.width: 1
                        border.color: reply.activeFocus ? "#8e8fe0" : "#4e4e4e"
                    }
                    onAccepted: {
                        if (text.trim() !== "")
                            root.replyRequested(root.entry.id, text, root.entry.revision ?? 0);
                    }
                }
                Notifications.ActionButton {
                    objectName: "toastSendReply"
                    fillColor: root.themeColors.toastButtonBackground
                    text: "Send"
                    enabled: reply.text.trim() !== ""
                    onClicked: root.replyRequested(root.entry.id, reply.text, root.entry.revision ?? 0)
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            root.revealFocus();
        }
    }
}
