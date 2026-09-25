pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common/Theme.js" as Theme

Item {
    id: root

    required property var conflictService
    signal closeRequested

    readonly property var conflict: root.conflictService.currentConflict
    readonly property var local: root.conflict ? root.conflict.local : null
    readonly property var remote: root.conflict ? root.conflict.remote : null
    property string selectedSide: ""
    property string selectedUid: ""
    property string selectedLocalIcs: ""
    property string selectedRemoteIcs: ""
    property bool confirmPending: false

    readonly property var fields: [
        {
            label: "WHEN",
            key: "start"
        },
        {
            label: "UNTIL",
            key: "end"
        },
        {
            label: "LOCATION",
            key: "location"
        },
        {
            label: "DESCRIPTION",
            key: "description"
        },
        {
            label: "REMINDERS",
            key: "reminders"
        }
    ]

    function value(data, key) {
        if (!data)
            return "Unavailable";
        if (key === "reminders")
            return data.reminders && data.reminders.length > 0 ? data.reminders.map(reminder => reminder.minutesBefore + " min before").join(", ") : "None";
        if (key === "allDay")
            return data.allDay ? "All day" : "Timed";
        return String(data[key] ?? "") || "None";
    }

    function differs(key) {
        return root.value(root.local, key) !== root.value(root.remote, key);
    }

    function confirmChoice() {
        if (root.selectedSide.length === 0 || root.conflictService.busy || !root.conflictService.stateValid)
            return;
        root.confirmPending = true;
        root.conflictService.choose(root.selectedSide);
    }

    function cancelChoice() {
        root.selectedSide = "";
        root.confirmPending = false;
        root.closeRequested();
    }

    Connections {
        target: root.conflictService
        function onConflictsChanged() {
            if (root.confirmPending && !root.conflictService.hasConflict)
                root.closeRequested();
            const uid = root.conflict ? root.conflict.uid : "";
            const localIcs = root.conflict ? root.conflict.localIcs : "";
            const remoteIcs = root.conflict ? root.conflict.remoteIcs : "";
            if (uid !== root.selectedUid || localIcs !== root.selectedLocalIcs || remoteIcs !== root.selectedRemoteIcs) {
                root.selectedSide = "";
                root.confirmPending = false;
                root.selectedUid = uid;
                root.selectedLocalIcs = localIcs;
                root.selectedRemoteIcs = remoteIcs;
            }
        }
        function onErrorMessageChanged() {
            if (root.conflictService.errorMessage.length > 0)
                root.confirmPending = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.closeRequested()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(720, Math.max(0, parent.width - 48))
        height: Math.min(650, Math.max(0, parent.height - 48))
        color: Theme.surface
        radius: 13
        border.width: 1
        border.color: Theme.border
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => mouse.accepted = true
        }

        Rectangle {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 65
            color: Qt.rgba(Theme.currentTime.r, Theme.currentTime.g, Theme.currentTime.b, 0.18)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: "Conflict"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: root.conflict ? ((root.conflictService.conflicts.indexOf(root.conflict) + 1) + " of " + root.conflictService.conflicts.length) : "No conflicts"
                color: Theme.textMuted
                font.family: Theme.font
                font.pixelSize: 12
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7
                text: root.conflict ? root.conflict.uid : ""
                textFormat: Text.PlainText
                color: Theme.textMuted
                font.pixelSize: 9
                elide: Text.ElideMiddle
                width: 150
                horizontalAlignment: Text.AlignRight
            }
        }

        Flickable {
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 36
            clip: true
            flickableDirection: Flickable.VerticalFlick

            ColumnLayout {
                id: contentColumn
                x: 20
                y: 18
                width: Math.max(0, parent.width - 40)
                spacing: 15

                Text {
                    Layout.fillWidth: true
                    text: "Choose complete event version. Unknown ICS properties stay unchanged."
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            {
                                label: "THIS DEVICE",
                                side: "local",
                                data: root.local
                            },
                            {
                                label: "OTHER DEVICE",
                                side: "remote",
                                data: root.remote
                            }
                        ]

                        delegate: Rectangle {
                            id: versionCard
                            required property var modelData
                            readonly property bool selected: root.selectedSide === modelData.side
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: cardContent.implicitHeight + 35
                            color: selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : cardHover.hovered ? Theme.surfaceRaised : Theme.background
                            radius: Theme.radius
                            border.width: selected ? 2 : 1
                            border.color: selected ? Theme.accent : cardHover.hovered ? Theme.textMuted : Theme.border

                            HoverHandler {
                                id: cardHover
                            }
                            TapHandler {
                                onTapped: root.selectedSide = versionCard.modelData.side
                            }

                            ColumnLayout {
                                id: cardContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                anchors.topMargin: 15
                                spacing: 11

                                Text {
                                    Layout.fillWidth: true
                                    text: versionCard.modelData.label
                                    color: versionCard.selected ? Theme.accent : Theme.textMuted
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.2
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.value(versionCard.modelData.data, "title")
                                    textFormat: Text.PlainText
                                    color: Theme.text
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Item {
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 0.5
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 20

                                    Repeater {
                                        model: root.fields
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                Layout.fillWidth: true
                                                text: parent.modelData.label
                                                color: Theme.textMuted
                                                font.pixelSize: 9
                                                font.letterSpacing: 1.2
                                                font.weight: Font.DemiBold
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 8
                                                text: root.value(versionCard.modelData.data, parent.modelData.key)
                                                textFormat: Text.PlainText
                                                color: root.differs(parent.modelData.key) ? Theme.currentTime : Theme.text
                                                font.pixelSize: 12
                                                wrapMode: Text.Wrap
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 1
                                                Layout.topMargin: 5
                                                color: Theme.border
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.conflictService.errorMessage.length > 0
                    text: root.conflictService.errorMessage
                    textFormat: Text.PlainText
                    color: Theme.currentTime
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        RowLayout {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 58
            anchors.leftMargin: 17
            anchors.rightMargin: 17
            anchors.bottomMargin: 5
            spacing: 8

            Rectangle {
                Layout.preferredWidth: confirmText.implicitWidth + 28
                Layout.preferredHeight: 34
                radius: Theme.radius
                color: confirmHover.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                opacity: !root.conflictService.busy && root.conflictService.stateValid && root.selectedSide.length > 0 ? 1 : 0.5
                Text {
                    id: confirmText
                    anchors.centerIn: parent
                    text: "Confirm"
                    color: Theme.background
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: confirmHover
                    enabled: !root.conflictService.busy && root.conflictService.stateValid && root.selectedSide.length > 0
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.conflictService.busy && root.conflictService.stateValid && root.selectedSide.length > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.confirmChoice()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.preferredWidth: cancelText.implicitWidth + 28
                Layout.preferredHeight: 34
                radius: Theme.radius
                color: cancelHover.hovered ? Theme.surfaceRaised : Theme.background
                border.width: 1
                border.color: Theme.border
                opacity: root.conflictService.busy ? 0.5 : 1
                Text {
                    id: cancelText
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: cancelHover
                    enabled: !root.conflictService.busy
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.conflictService.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelChoice()
                }
            }
        }
    }
}
