import QtQuick
import QtQuick.Layouts
import "../common/Theme.js" as Theme

Rectangle {
    id: root

    required property var eventData
    required property bool selected
    property bool compact: false
    property color eventColor: root.eventData.color || Theme.accent
    readonly property color selectionColor: Qt.lighter(root.eventColor, 1.18)

    signal selectionRequested(var eventData)
    signal activated(var eventData)

    radius: Theme.radius
    color: root.selected ? Qt.rgba(root.selectionColor.r, root.selectionColor.g, root.selectionColor.b, 0.28) : Qt.rgba(root.eventColor.r, root.eventColor.g, root.eventColor.b, 0.2)
    border.width: 1
    border.color: root.selected ? Qt.rgba(root.selectionColor.r, root.selectionColor.g, root.selectionColor.b, 0.72) : Qt.rgba(root.eventColor.r, root.eventColor.g, root.eventColor.b, 0.65)
    clip: true

    Rectangle {
        width: 3
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: 1.5
        anchors.bottomMargin: 1.5
        anchors.leftMargin: 0.7
        radius: 20
        color: root.selected ? root.selectionColor : root.eventColor
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 9
        anchors.rightMargin: 6
        anchors.topMargin: root.compact ? 5 : 8
        y: 20
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.eventData.title
            color: Theme.text
            font.pixelSize: root.compact ? 11 : 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: root.compact ? 1 : 2
            wrapMode: Text.Wrap
        }

        Text {
            visible: !root.compact
            Layout.fillWidth: true
            text: Qt.formatTime(new Date(root.eventData.displayStartMs ?? root.eventData.startMs), "HH:mm") + " - " + Qt.formatTime(new Date(root.eventData.displayEndMs ?? root.eventData.endMs), "HH:mm")
            color: Theme.textMuted
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        Text {
            visible: !root.compact && root.eventData.location.length > 0
            Layout.fillWidth: true
            text: root.eventData.location
            color: Theme.textMuted
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const event = root.eventData.sourceEvent ?? root.eventData;
            root.selectionRequested(event);
        }
        onDoubleClicked: {
            const event = root.eventData.sourceEvent ?? root.eventData;
            root.selectionRequested(event);
            root.activated(event);
        }
    }
}
