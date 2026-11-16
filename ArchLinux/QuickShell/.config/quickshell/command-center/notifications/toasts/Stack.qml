pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../../components"
import "../../common/Theme.js" as Theme

FocusScope {
    id: root

    property var entries: []
    property var themeColors: Theme.colors
    property real requestedHeight: 0
    property real maximumHeight: 900
    property string feedback: ""
    signal dismissRequested(var entryId, var revision)
    signal actionRequested(var entryId, string action, var revision)
    signal replyRequested(var entryId, string text, var revision)
    signal copyCodeRequested(string code)
    signal copyRequested(var entryId, var revision)
    signal interactionChanged(var entryId, bool hovered, bool focused)

    KeyedModel {
        id: toastModel
        entries: root.entries
    }

    implicitHeight: Math.max(0, Math.min(root.maximumHeight, cards.implicitHeight))
    height: implicitHeight

    function focusContent(): void {
        root.forceActiveFocus(Qt.MouseFocusReason);
    }

    function revealFocus(): void {
        let item = root.Window.window?.activeFocusItem;
        if (!root.activeFocus || !item)
            return;
        while (item && item.parent !== cards)
            item = item.parent;
        if (!item)
            return;
        const point = item.mapToItem(scroll.contentItem, 0, 0);
        const maximum = Math.max(0, scroll.contentHeight - scroll.height);
        if (point.y < scroll.contentY)
            scroll.contentY = Math.max(0, Math.min(maximum, point.y));
        else if (point.y + item.height > scroll.contentY + scroll.height)
            scroll.contentY = Math.max(0, Math.min(maximum, point.y + item.height - scroll.height));
    }

    Flickable {
        id: scroll
        objectName: "toastStackScroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: cards.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onHeightChanged: Qt.callLater(root.revealFocus)
        ScrollBar.vertical: ScrollBar {
            width: 4
        }

        Column {
            id: cards
            width: scroll.width
            spacing: 8

            Repeater {
                model: toastModel
                delegate: Toast {
                    required property var key
                    readonly property var modelData: toastModel.byKey.get(key) || ({})
                    objectName: "toast" + modelData.id
                    width: cards.width
                    entry: modelData
                    themeColors: root.themeColors
                    requestedHeight: root.requestedHeight
                    maximumHeight: root.maximumHeight
                    onDismissRequested: (entryId, revision) => root.dismissRequested(entryId, revision)
                    onActionRequested: (entryId, action, revision) => root.actionRequested(entryId, action, revision)
                    onReplyRequested: (entryId, text, revision) => root.replyRequested(entryId, text, revision)
                    onCopyCodeRequested: code => root.copyCodeRequested(code)
                    onCopyRequested: (entryId, revision) => root.copyRequested(entryId, revision)
                    onInteractionChanged: (entryId, hovered, focused) => root.interactionChanged(entryId, hovered, focused)
                }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: root.feedback
                color: root.themeColors.text
                font.family: Theme.textFont
                font.pixelSize: 12
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            root.revealFocus();
        }
    }
}
