pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    required property var colors
    required property var versions
    property string currentVersion: ""
    signal selectRequested(string name)
    readonly property bool menuOpen: geMenu.visible
    readonly property int rowHeight: 30
    readonly property int currentIndex: Math.max(0, versions.indexOf(currentVersion))
    readonly property int visibleRowsAbove: Math.min(currentIndex, Math.max(1, 2 - (versions.length - currentIndex - 1)))
    readonly property int visibleRowsBelow: Math.max(0, Math.min(versions.length - currentIndex - 1, 2 - visibleRowsAbove))
    implicitHeight: 34
    Layout.fillWidth: true
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: "Current Proton " + (currentVersion || "not selected")
    Keys.onSpacePressed: toggleMenu()
    Keys.onReturnPressed: toggleMenu()
    onEnabledChanged: {
        if (!enabled)
            geMenu.close();
    }
    onVisibleChanged: {
        if (!visible)
            geMenu.close();
    }
    function closeMenu() {
        geMenu.close();
    }
    function toggleMenu() {
        if (geMenu.visible)
            geMenu.close();
        else if (root.enabled && root.versions.length)
            geMenu.open();
    }
    function positionWheel() {
        const position = root.mapToItem(geMenu.parent, 0, root.height - 1);
        geMenu.x = position.x;
        geMenu.y = position.y;
    }
    Rectangle {
        id: geFieldSurface
        anchors.fill: parent
        color: geFieldMouse.pressed ? root.colors.buttonHover : !geMenu.visible && geFieldMouse.containsMouse ? root.colors.cardHover : root.colors.tab
        border.color: root.colors.border
        radius: 5
        bottomLeftRadius: geMenu.visible ? 0 : 5
        bottomRightRadius: geMenu.visible ? 0 : 5
        Text {
            anchors.fill: parent
            text: root.currentVersion || (root.versions.length ? "Choose GE" : "No installed GE")
            color: root.enabled ? root.colors.accent : root.colors.secondary
            font.family: root.theme.fontFamily
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: root.colors.secondary
            font.family: root.theme.fontFamily
            font.pixelSize: 12
        }
        MouseArea {
            id: geFieldMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.toggleMenu()
        }
    }
    Popup {
        id: geMenu
        parent: root
        z: 1000
        width: root.width
        height: (root.visibleRowsAbove + 1 + root.visibleRowsBelow) * root.rowHeight + bottomPadding
        padding: 0
        bottomPadding: 6
        focus: true
        modal: false
        dim: false
        clip: true
        popupType: Popup.Item
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onAboutToShow: root.positionWheel()
        contentItem: Item {
            clip: true
            Loader {
                y: -(2 - root.visibleRowsAbove) * root.rowHeight
                width: parent.width
                height: 5 * root.rowHeight
                active: geMenu.visible
                sourceComponent: Component {
                    Tumbler {
                        id: geWheel
                        model: root.versions
                        currentIndex: root.currentIndex
                        visibleItemCount: 5
                        wrap: false
                        focus: true
                        Keys.onReturnPressed: {
                            if (currentIndex >= 0 && currentIndex < root.versions.length)
                                root.selectRequested(root.versions[currentIndex]);
                            geMenu.close();
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: 2
                            acceptedButtons: Qt.NoButton
                            onWheel: event => {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
                                if (delta !== 0)
                                    geWheel.currentIndex = Math.max(0, Math.min(root.versions.length - 1, geWheel.currentIndex + (delta < 0 ? 1 : -1)));
                                event.accepted = true;
                            }
                        }
                        background: Item {
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: 24
                                color: root.colors.cardHover
                                radius: 6
                            }
                        }
                        delegate: Item {
                            id: wheelEntry
                            required property int index
                            required property string modelData
                            readonly property real displacement: Tumbler.displacement
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                radius: 6
                                color: geEntryTap.pressed ? root.colors.buttonHover : geEntryHover.hovered ? root.colors.entryHover : "transparent"
                            }
                            Text {
                                anchors.fill: parent
                                text: wheelEntry.modelData
                                color: geEntryTap.pressed ? root.colors.pressedText : geEntryHover.hovered ? root.colors.hoverText : Math.abs(wheelEntry.displacement) < 0.5 ? root.colors.foreground : root.colors.secondary
                                opacity: geEntryHover.hovered ? 1 : Math.max(0.35, 1 - Math.abs(wheelEntry.displacement) * 0.24)
                                font.family: root.theme.fontFamily
                                font.pixelSize: 13
                                font.bold: Math.abs(wheelEntry.displacement) < 0.5
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.currentVersion === wheelEntry.modelData
                                text: "➜"
                                color: root.colors.accent
                                font.family: root.theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                            }
                            HoverHandler {
                                id: geEntryHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: geEntryTap
                                onTapped: {
                                    geWheel.currentIndex = wheelEntry.index;
                                    root.selectRequested(wheelEntry.modelData);
                                    geMenu.close();
                                }
                            }
                        }
                    }
                }
            }
        }
        background: Rectangle {
            color: geFieldSurface.color
            border.color: root.colors.border
            radius: 5
            topLeftRadius: 0
            topRightRadius: 0
            Rectangle {
                x: 1
                width: Math.max(0, parent.width - 2)
                height: 1
                color: geFieldSurface.color
            }
        }
    }
}
