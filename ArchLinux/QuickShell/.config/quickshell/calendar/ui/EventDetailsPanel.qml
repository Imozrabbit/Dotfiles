pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common/CalendarMath.js" as CalendarMath
import "../common/Theme.js" as Theme

Rectangle {
    id: root

    required property var eventData
    required property var calendarService
    readonly property var details: eventData ? CalendarMath.eventDetails(eventData, calendarService.calendars) : null
    readonly property color eventColor: details ? details.color : Theme.accent
    readonly property bool writable: eventData && eventData.readOnly !== true
    property bool confirmingDelete: false
    property string actionError: ""

    signal closeRequested
    signal editRequested(var eventData)
    signal deleted(string uid)

    color: Theme.surface
    radius: 13
    border.width: 1
    border.color: Theme.border
    clip: true
    focus: true

    Keys.onEscapePressed: event => {
        root.closeRequested();
        event.accepted = true;
    }

    Component.onCompleted: root.forceActiveFocus()

    component ActionButton: Rectangle {
        id: actionButton

        required property string label
        property bool primary: false
        property bool destructive: false
        signal clicked

        implicitWidth: Math.max(80, buttonLabel.implicitWidth + 28)
        implicitHeight: 34
        radius: Theme.radius
        color: primary ? Theme.accent : buttonHover.hovered ? Theme.surfaceRaised : Theme.background
        border.width: primary ? 0 : 1
        border.color: destructive ? Theme.currentTime : Theme.border

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: actionButton.label
            color: actionButton.primary ? Theme.background : actionButton.destructive ? Theme.currentTime : Theme.text
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: actionButton.clicked()
        }
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() && left.getDate() === right.getDate();
    }

    function timeLabel() {
        if (!root.details)
            return "Time unavailable";
        const start = new Date(root.details.startMs);
        const displayEnd = new Date(root.details.displayEndMs);
        if (root.details.allDay) {
            if (root.sameDay(start, displayEnd))
                return Qt.formatDate(start, "dddd, MMMM d, yyyy") + " · All day";
            return Qt.formatDate(start, "MMM d, yyyy") + " – " + Qt.formatDate(displayEnd, "MMM d, yyyy") + " · All day";
        }
        const end = new Date(root.details.endMs);
        if (root.sameDay(start, end)) {
            const startTime = Qt.formatTime(start, "HH:mm");
            const endTime = Qt.formatTime(end, "HH:mm");
            if (startTime === endTime && end.getTime() > start.getTime())
                return Qt.formatDate(start, "dddd, MMMM d, yyyy") + " · " + Qt.formatDateTime(start, "HH:mm t") + "–" + Qt.formatDateTime(end, "HH:mm t");
            return Qt.formatDate(start, "dddd, MMMM d, yyyy") + " · " + startTime + "–" + endTime;
        }
        return Qt.formatDate(start, "MMM d, yyyy") + " " + Qt.formatTime(start, "HH:mm") + " – " + Qt.formatDate(end, "MMM d, yyyy") + " " + Qt.formatTime(end, "HH:mm");
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        onPressed: root.forceActiveFocus()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        topLeftRadius: root.radius
        topRightRadius: root.radius
        bottomLeftRadius: 0
        bottomRightRadius: 0
        color: Qt.rgba(root.eventColor.r, root.eventColor.g, root.eventColor.b, 0.18)

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.right: closeButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            transform: Translate {
                y: 2
            }
            text: root.details ? root.details.title : "Untitled"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Rectangle {
            id: closeButton

            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            width: 20
            height: 20
            radius: 16
            color: closeHover.hovered ? Theme.surfaceRaised : Theme.surface
            border.width: 0
            border.color: Theme.border

            Text {
                anchors.centerIn: parent
                text: ""
                color: Theme.text
                font.pixelSize: 18
            }

            HoverHandler {
                id: closeHover
                cursorShape: Qt.PointingHandCursor
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }

    Flickable {
        id: detailsFlickable

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionFooter.top
        contentWidth: width
        contentHeight: detailsColumn.height + 50
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: detailsColumn

            x: 20
            y: 20
            width: Math.max(0, detailsFlickable.width - 40)
            spacing: 14

            Text {
                text: "WHEN"
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.timeLabel()
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            Text {
                text: "CALENDAR"
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    Layout.alignment: Qt.AlignVCenter
                    radius: 5
                    color: root.eventColor
                }

                Text {
                    Layout.fillWidth: true
                    text: root.details ? root.details.calendarName : "Unknown calendar"
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            Text {
                text: "LOCATION"
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.details ? root.details.location : "No location"
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            Text {
                text: "DESCRIPTION"
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.details ? root.details.description : "No description"
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            Text {
                text: "REMINDERS"
                color: Theme.textMuted
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.details ? root.details.reminders : []

                delegate: Text {
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.leftMargin: 2
                    text: "- " + modelData
                    color: Theme.text
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
            }

            Text {
                visible: root.details && root.details.reminders.length === 0
                Layout.fillWidth: true
                text: "No reminders"
                color: Theme.textMuted
                font.pixelSize: 13
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            Rectangle {
                implicitWidth: statusText.implicitWidth + 18
                implicitHeight: 28
                radius: 14
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.border

                Text {
                    id: statusText

                    anchors.centerIn: parent
                    text: root.details ? root.details.status : "Read-only"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }
    }

    Item {
        id: actionFooter

        visible: root.writable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: visible ? footerContent.implicitHeight + 24 : 0

        ColumnLayout {
            id: footerContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 15
            spacing: 8

            RowLayout {
                visible: !root.confirmingDelete
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 34 : 0
                spacing: 8

                ActionButton {
                    label: "Edit"
                    primary: true
                    onClicked: root.editRequested(root.eventData)
                }

                Item {
                    Layout.fillWidth: true
                }

                ActionButton {
                    label: "Delete"
                    destructive: true
                    onClicked: {
                        root.actionError = "";
                        root.confirmingDelete = true;
                    }
                }
            }

            RowLayout {
                visible: root.confirmingDelete
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 34 : 0
                spacing: 8

                ActionButton {
                    label: "Delete permanently"
                    destructive: true
                    onClicked: {
                        const result = root.calendarService.deleteEvent(root.eventData.uid);
                        if (result.ok)
                            root.deleted(result.uid);
                        else
                            root.actionError = result.message;
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ActionButton {
                    label: "Cancel"
                    onClicked: {
                        root.confirmingDelete = false;
                        root.actionError = "";
                    }
                }
            }

            Text {
                visible: root.actionError.length > 0
                Layout.fillWidth: true
                text: root.actionError
                color: Theme.currentTime
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }
}
