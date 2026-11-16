pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../common/Theme.js" as Theme

Item {
    id: root

    property var entries: []
    property bool clearEnabled: true
    property var expandedApps: Object.create(null)
    property var themeColors: Theme.colors
    readonly property var groups: {
        const result = [];
        for (const entry of root.entries) {
            const name = entry.appName || "Notification";
            let group = result.find(item => item.name === name);
            if (!group) {
                group = {
                    name: name,
                    entries: []
                };
                result.push(group);
            }
            group.entries.push(entry);
        }
        return result;
    }
    signal dismissRequested(var entryId, var revision)
    signal dismissGroupRequested(string appName)
    signal openRequested(var entryId)
    signal copyCodeRequested(string code)
    signal actionRequested(var entryId, string action, var revision)
    signal replyRequested(var entryId, string text, var revision)

    KeyedModel {
        id: groupModel
        entries: root.groups
        keyRole: "name"
    }

    implicitHeight: root.entries.length ? groupsColumn.implicitHeight + 12 : 0
    height: implicitHeight
    visible: root.entries.length > 0

    function localImage(source) {
        if (typeof source !== "string")
            return "";
        return source.startsWith("/") || source.startsWith("file://") || source.startsWith("qrc:/") || source.startsWith("image://") || source.startsWith("data:image/") ? source : "";
    }

    function setExpanded(appName: string, expanded: bool): void {
        const next = Object.assign(Object.create(null), root.expandedApps);
        next[appName] = expanded;
        root.expandedApps = next;
    }

    onEntriesChanged: {
        const present = new Set(root.entries.map(entry => entry.appName || "Notification"));
        const next = Object.create(null);
        for (const name of Object.keys(root.expandedApps)) {
            if (present.has(name))
                next[name] = root.expandedApps[name];
        }
        root.expandedApps = next;
    }

    Flickable {
        id: historyScroll
        objectName: "historyScroll"
        x: 6
        y: 6
        width: Math.max(0, root.width - 12)
        height: Math.max(0, root.height - 12)
        contentWidth: width
        contentHeight: groupsColumn.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: groupsColumn
            width: historyScroll.width
            spacing: 12

            Repeater {
                model: groupModel

                delegate: Column {
                    id: group
                    required property var key
                    readonly property var modelData: groupModel.byKey.get(key) || ({
                            name: "",
                            entries: []
                        })
                    required property int index
                    objectName: "notificationGroup" + group.index
                    readonly property bool expanded: modelData.entries.length < 2 || root.expandedApps[modelData.name] === true
                    readonly property int stackDepth: expanded ? 0 : Math.min(2, modelData.entries.length - 1)
                    width: groupsColumn.width
                    spacing: 5
                    bottomPadding: stackDepth * 6

                    KeyedModel {
                        id: entryModel
                        entries: group.modelData.entries
                    }

                    Repeater {
                        model: entryModel

                        delegate: Rectangle {
                            id: card
                            required property var key
                            readonly property var modelData: entryModel.byKey.get(key) || ({})
                            required property int index
                            readonly property bool collapsedStack: card.index === 0 && group.stackDepth > 0
                            objectName: "notification" + card.modelData.id
                            width: group.width
                            visible: group.expanded || card.index === 0
                            implicitHeight: Math.max(56, content.implicitHeight + 16)
                            height: implicitHeight
                            radius: Theme.radius
                            color: cardAction.down ? Qt.darker(root.themeColors.tileHover, 1.2) : cardAction.hovered || cardAction.visualFocus ? root.themeColors.tileHover : root.themeColors.notificationSurface
                            border.color: root.themeColors.sectionBorder
                            border.width: border.color.a > 0 ? 1 : 0

                            Item {
                                id: stack
                                objectName: "notificationStack" + card.modelData.id
                                y: card.height
                                width: card.width
                                height: group.bottomPadding
                                visible: card.index === 0 && group.stackDepth > 0
                                clip: true

                                Repeater {
                                    model: stack.visible ? group.stackDepth : 0
                                    delegate: Item {
                                        id: stackLayer
                                        required property int index
                                        objectName: "notificationStackLayer" + index
                                        x: (index + 1) * 6
                                        y: index * 6
                                        width: Math.max(0, stack.width - x * 2)
                                        height: 6
                                        // Paint only exposed edge, avoiding doubled translucent fill.
                                        clip: true

                                        Rectangle {
                                            width: parent.width
                                            height: card.height
                                            y: parent.height - height
                                            radius: card.radius
                                            color: Qt.lighter(card.color, 1.6)
                                            opacity: stackLayer.index === 0 ? 0.85 : 0.6
                                        }
                                    }
                                }
                            }

                            Button {
                                id: cardAction
                                objectName: "notificationAction" + card.modelData.id
                                anchors.fill: parent
                                enabled: card.collapsedStack || card.modelData.canOpen === true
                                hoverEnabled: true
                                Accessible.name: card.collapsedStack ? "Expand " + group.modelData.name : "Open " + (card.modelData.summary || group.modelData.name)
                                Accessible.description: card.modelData.body || ""
                                Accessible.ignored: !enabled
                                contentItem: Item {}
                                background: Item {}
                                onClicked: {
                                    if (card.collapsedStack)
                                        root.setExpanded(group.modelData.name, true);
                                    else
                                        root.openRequested(card.modelData.id);
                                }

                                HoverHandler {
                                    enabled: cardAction.enabled
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            ColumnLayout {
                                id: content
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 38
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: Theme.radius
                                        color: root.themeColors.tile

                                        Text {
                                            objectName: "notificationInitial" + card.modelData.id
                                            anchors.fill: parent
                                            visible: avatar.status !== Image.Ready
                                            text: group.modelData.name.charAt(0).toUpperCase()
                                            color: root.themeColors.text
                                            font.family: Theme.textFont
                                            font.pixelSize: 18
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            textFormat: Text.PlainText
                                            Accessible.ignored: true
                                        }
                                        Image {
                                            id: avatar
                                            objectName: "notificationAvatar" + card.modelData.id
                                            anchors.fill: parent
                                            source: root.localImage(card.modelData.appIcon)
                                            sourceSize.width: 76
                                            sourceSize.height: 76
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 2

                                        RowLayout {
                                            id: header
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: card.modelData.summary || group.modelData.name
                                                color: root.themeColors.text
                                                font.family: Theme.textFont
                                                font.pixelSize: 14
                                                font.bold: true
                                                elide: Text.ElideRight
                                                textFormat: Text.PlainText
                                            }
                                            Text {
                                                id: timestamp
                                                Layout.maximumWidth: header.width / 3
                                                text: card.modelData.time || ""
                                                visible: text !== ""
                                                color: root.themeColors.muted
                                                font.family: Theme.textFont
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                                textFormat: Text.PlainText
                                            }
                                            ActionTile {
                                                id: collapseButton
                                                themeColors: root.themeColors
                                                objectName: card.index === 0 ? "groupCollapse" + group.index : ""
                                                visible: card.index === 0 && group.expanded && group.modelData.entries.length > 1
                                                glyph: "󰅃"
                                                tooltip: "Collapse " + group.modelData.name
                                                implicitWidth: 26
                                                implicitHeight: 26
                                                fillColor: "transparent"
                                                lineColor: "transparent"
                                                onClicked: {
                                                    const reason = collapseButton.focusReason;
                                                    root.setExpanded(group.modelData.name, false);
                                                    cardAction.forceActiveFocus(reason);
                                                }
                                            }
                                            ActionTile {
                                                themeColors: root.themeColors
                                                objectName: "dismiss" + card.modelData.id
                                                enabled: root.clearEnabled
                                                glyph: "󰅖"
                                                tooltip: card.collapsedStack ? "Clear " + group.modelData.name : "Clear notification"
                                                implicitWidth: 26
                                                implicitHeight: 26
                                                fillColor: "transparent"
                                                lineColor: "transparent"
                                                onClicked: {
                                                    if (card.collapsedStack)
                                                        root.dismissGroupRequested(group.modelData.name);
                                                    else
                                                        root.dismissRequested(card.modelData.id, card.modelData.revision ?? 0);
                                                }
                                            }
                                        }
                                        Text {
                                            objectName: "body" + card.modelData.id
                                            Layout.fillWidth: true
                                            text: card.modelData.body || ""
                                            visible: text !== ""
                                            color: root.themeColors.text
                                            font.family: Theme.textFont
                                            font.pixelSize: 13
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 5
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 16
                                    implicitHeight: preview.status === Image.Ready ? 150 : 40
                                    visible: card.modelData.imageExpected === true || !!card.modelData.image
                                    Image {
                                        id: preview
                                        objectName: "notificationImage" + card.modelData.id
                                        anchors.fill: parent
                                        source: root.localImage(card.modelData.image)
                                        sourceSize: Qt.size(300, 150)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        objectName: "notificationImageUnavailable" + card.modelData.id
                                        anchors.centerIn: parent
                                        visible: preview.status !== Image.Ready
                                        text: "Unavailable"
                                        color: root.themeColors.muted
                                        font.family: Theme.textFont
                                        font.pixelSize: 12
                                        textFormat: Text.PlainText
                                    }
                                }
                                Grid {
                                    id: actionGrid
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.topMargin: 16
                                    columns: 3
                                    spacing: 6
                                    visible: (card.modelData.actions || []).length > 0
                                    Repeater {
                                        model: card.modelData.actions || []
                                        delegate: ActionButton {
                                            required property var modelData
                                            objectName: "notificationAction-" + card.modelData.id + "-" + modelData.id
                                            fillColor: root.themeColors.toastButtonBackground
                                            fontFamily: Theme.textFont
                                            text: modelData.text
                                            width: Math.max(0, (actionGrid.width - 2 * actionGrid.spacing) / 3)
                                            onClicked: root.actionRequested(card.modelData.id, modelData.id, card.modelData.revision ?? 0)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 16
                                    spacing: 6
                                    visible: card.modelData.hasInlineReply === true
                                    TextField {
                                        id: reply
                                        objectName: "notificationReplyInput" + card.modelData.id
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        placeholderText: card.modelData.inlineReplyPlaceholder || "Reply"
                                        Accessible.name: placeholderText
                                        color: root.themeColors.text
                                        font.family: Theme.textFont
                                        font.pixelSize: 12
                                        selectByMouse: true
                                        onAccepted: {
                                            if (text.trim() !== "")
                                                root.replyRequested(card.modelData.id, text, card.modelData.revision ?? 0);
                                        }
                                    }
                                    ActionButton {
                                        objectName: "notificationSendReply" + card.modelData.id
                                        fillColor: root.themeColors.toastButtonBackground
                                        fontFamily: Theme.textFont
                                        text: "Send"
                                        enabled: reply.text.trim() !== ""
                                        onClicked: root.replyRequested(card.modelData.id, reply.text, card.modelData.revision ?? 0)
                                    }
                                }
                                ActionTile {
                                    Layout.topMargin: 16
                                    themeColors: root.themeColors
                                    objectName: "copyCode" + card.modelData.id
                                    visible: !!card.modelData.twoFactorCode
                                    glyph: "󰆏"
                                    tooltip: "Copy code"
                                    implicitWidth: 28
                                    implicitHeight: 26
                                    onClicked: root.copyCodeRequested(card.modelData.twoFactorCode)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
