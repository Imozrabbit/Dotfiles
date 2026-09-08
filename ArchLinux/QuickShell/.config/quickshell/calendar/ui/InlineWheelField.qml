pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../common/Theme.js" as Theme

Item {
    id: root

    required property string label
    required property var model
    required property int currentIndex
    required property string displayText
    property bool editable: false
    property string text: ""
    property bool expanded: false
    property bool invalid: false
    property bool padNumbers: false
    property bool trimModelEnds: true
    readonly property int labelHeight: 14
    readonly property int collapsedHeight: 34
    readonly property int availableRowsAbove: Math.max(0, currentIndex)
    readonly property int availableRowsBelow: Math.max(0, model.length - currentIndex - 1)
    readonly property int visibleRowsAbove: trimModelEnds ? Math.min(availableRowsAbove, Math.max(1, 2 - availableRowsBelow)) : 2
    readonly property int visibleRowsBelow: trimModelEnds ? Math.min(availableRowsBelow, 2 - visibleRowsAbove) : 2
    readonly property int visibleRowCount: visibleRowsAbove + 1 + visibleRowsBelow

    signal expansionRequested
    signal collapseRequested
    signal selectionRequested(int index, var value)
    signal textEdited(string text)

    function positionPopup() {
        const position = root.mapToItem(wheelPopup.parent, 0, root.labelHeight - root.visibleRowsAbove * root.collapsedHeight);
        wheelPopup.x = position.x;
        wheelPopup.y = position.y;
    }

    height: labelHeight + collapsedHeight

    Text {
        x: 5
        width: parent.width - x
        height: root.labelHeight
        text: root.label
        color: Theme.textMuted
        font.pixelSize: 8
        font.letterSpacing: 0.8
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Rectangle {
        id: collapsedField

        x: 0
        y: root.labelHeight
        width: parent.width
        height: root.collapsedHeight
        radius: Theme.radius
        color: Theme.background
        border.width: 1
        border.color: root.invalid ? Theme.currentTime : Theme.border

        Text {
            visible: !root.editable
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: pickerChevron.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayText
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Controls.TextField {
            visible: root.editable
            anchors.fill: parent
            rightPadding: 30
            leftPadding: 7
            text: root.text
            color: Theme.text
            placeholderTextColor: Theme.textMuted
            selectionColor: Theme.accent
            selectedTextColor: Theme.background
            font.family: Theme.fontMono
            font.pixelSize: 12
            horizontalAlignment: TextInput.AlignHCenter
            background: Item {}
            Keys.onEscapePressed: event => {
                if (root.expanded)
                    root.collapseRequested();
                else
                    collapsedField.forceActiveFocus();
                event.accepted = true;
            }
            onTextEdited: root.textEdited(text)
        }

        Text {
            id: pickerChevron

            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: "v"
            color: Theme.textMuted
            font.family: Theme.font
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        MouseArea {
            visible: !root.editable
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expansionRequested()
        }

        MouseArea {
            visible: root.editable
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 28
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expansionRequested()
        }
    }

    Controls.Popup {
        id: wheelPopup

        parent: Controls.Overlay.overlay
        z: 1000
        width: root.width
        height: root.visibleRowCount * root.collapsedHeight
        padding: 0
        modal: false
        dim: false
        clip: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Theme.radius
            color: Theme.background
            border.width: 1
            border.color: root.invalid ? Theme.currentTime : Theme.border
        }
        contentItem: Item {
            clip: true

            Loader {
                x: 0
                y: -(2 - root.visibleRowsAbove) * root.collapsedHeight
                width: parent.width
                height: 5 * root.collapsedHeight
                active: wheelPopup.visible
                sourceComponent: wheelComponent
            }
        }
        onClosed: {
            if (root.expanded)
                root.collapseRequested();
        }
    }

    onExpandedChanged: {
        if (root.expanded && !wheelPopup.opened) {
            root.positionPopup();
            wheelPopup.open();
        } else if (!root.expanded && wheelPopup.opened) {
            wheelPopup.close();
        }
    }

    onVisibleRowsAboveChanged: {
        if (wheelPopup.opened)
            root.positionPopup();
    }

    Component {
        id: wheelComponent

        Controls.Tumbler {
            id: wheel

            property bool ready: false

            model: root.model
            currentIndex: root.currentIndex
            visibleItemCount: 5
            wrap: false

            MouseArea {
                anchors.fill: parent
                z: 2
                acceptedButtons: Qt.NoButton

                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
                    if (delta !== 0)
                        wheel.currentIndex = Math.max(0, Math.min(root.model.length - 1, wheel.currentIndex + (delta < 0 ? 1 : -1)));
                    event.accepted = true;
                }
            }

            background: Item {
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    height: 27
                    radius: Math.max(0, Theme.radius - 2)
                    color: Theme.surfaceRaised
                }
            }
            delegate: Text {
                required property int index
                required property var modelData

                text: root.padNumbers && typeof modelData === "number" ? String(modelData).padStart(2, "0") : String(modelData)
                color: Math.abs(Controls.Tumbler.displacement) < 0.5 ? Theme.text : Theme.textMuted
                opacity: Math.max(0.35, 1 - Math.abs(Controls.Tumbler.displacement) * 0.24)
                font.family: typeof modelData === "number" ? Theme.fontMono : Theme.font
                font.pixelSize: 12
                font.weight: Math.abs(Controls.Tumbler.displacement) < 0.5 ? Font.DemiBold : Font.Normal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Component.onCompleted: ready = true
            onCurrentIndexChanged: {
                if (ready && currentIndex >= 0 && currentIndex < root.model.length)
                    root.selectionRequested(currentIndex, root.model[currentIndex]);
            }
        }
    }
}
