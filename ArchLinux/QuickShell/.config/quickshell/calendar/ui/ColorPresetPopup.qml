pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import "../common/Theme.js" as Theme
import "../common/ColorPresets.js" as ColorPresets

Controls.Control {
    id: root

    required property Item selector
    required property Controls.ScrollView viewport
    required property var colors
    required property string selectedColor
    property bool opened: false
    property string removalColor: ""
    readonly property int columns: Math.max(1, Math.floor(availableWidth / 40))
    signal colorPicked(string color)
    signal colorRemovalRequested(string color)

    // A Popup would escape the form's clipping through the window overlay.
    parent: root.selector
    enabled: root.selector.enabled
    visible: root.opened
    x: root.selector.width - width
    y: -height - 6
    implicitWidth: root.colors.length ? 16 + Math.min(6, root.colors.length) * 40 : 128
    width: Math.min(implicitWidth, Math.max(0, root.viewport.width))
    height: Math.min(implicitHeight, Math.max(0, root.viewport.height - 16))
    implicitHeight: 16 + Math.max(1, Math.min(4, Math.ceil(root.colors.length / root.columns))) * 40
    padding: 8
    z: 1000

    function open() {
        if (!root.enabled)
            return;
        root.removalColor = "";
        root.opened = true;
        const flickable = root.viewport.contentItem as Flickable;
        if (flickable) {
            const top = root.mapToItem(root.viewport, 0, 0).y;
            const offset = top < 8 ? top - 8 : Math.max(0, top + root.height - root.viewport.height + 8);
            flickable.contentY = Math.max(0, Math.min(flickable.contentHeight - flickable.height, flickable.contentY + offset));
        }
        grid.currentIndex = Math.max(0, root.colors.indexOf(ColorPresets.normalizeColor(root.selectedColor)));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        grid.forceActiveFocus();
    }

    function close() {
        if (!root.opened)
            return;
        root.removalColor = "";
        root.opened = false;
        if (root.selector.enabled)
            root.selector.forceActiveFocus();
    }

    function select(index) {
        if (!root.enabled || index < 0 || index >= root.colors.length)
            return;
        root.colorPicked(root.colors[index]);
        root.close();
    }

    Keys.onEscapePressed: {
        if (root.removalColor)
            root.removalColor = "";
        else
            root.close();
    }
    onColorsChanged: root.removalColor = ""
    onEnabledChanged: {
        if (!enabled)
            close();
    }
    MouseArea {
        id: outsidePress
        // Handle dismissal before accepting form MouseAreas.
        parent: root.selector.Window.window?.contentItem || null
        anchors.fill: parent
        visible: root.opened
        z: 10000
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const inViewport = root.viewport.contains(root.viewport.mapFromItem(outsidePress, mouse.x, mouse.y));
            const inAction = inViewport && removeAction.visible && removeAction.contains(removeAction.mapFromItem(outsidePress, mouse.x, mouse.y));
            const inPalette = inViewport && root.contains(root.mapFromItem(outsidePress, mouse.x, mouse.y));
            if (root.removalColor && !inAction) {
                root.removalColor = "";
                mouse.accepted = true;
                return;
            }
            if (!inAction && !inPalette)
                root.close();
            mouse.accepted = false;
        }
    }
    background: Rectangle {
        color: Theme.background
        radius: Theme.radius
        border.width: 1
        border.color: Theme.border
    }
    contentItem: GridView {
        id: grid
        objectName: "calendarColorPresetGrid"
        model: root.colors
        cellWidth: 40
        cellHeight: 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        onContentYChanged: root.removalColor = ""
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.select(grid.currentIndex);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                grid.currentIndex = event.key === Qt.Key_Home ? 0 : grid.count - 1;
                grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
        delegate: Item {
            id: entry
            required property int index
            required property string modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Controls.Button {
                id: colorButton
                objectName: "calendarColorPreset-" + entry.index
                readonly property bool selected: ColorPresets.normalizeColor(root.selectedColor) === entry.modelData
                anchors.fill: parent
                anchors.margins: 3
                hoverEnabled: true
                Accessible.name: "Use " + entry.modelData
                Accessible.description: selected ? "Current color" : ""
                onClicked: root.select(entry.index)
                onActiveFocusChanged: {
                    if (activeFocus) {
                        grid.currentIndex = entry.index;
                        grid.positionViewAtIndex(entry.index, GridView.Contain);
                    }
                }
                Keys.onReturnPressed: root.select(entry.index)
                Keys.onEnterPressed: root.select(entry.index)
                background: Rectangle {
                    radius: Theme.radius
                    color: colorButton.down || (swatchMouse.pressed && swatchMouse.pressedButtons === Qt.LeftButton) ? Qt.darker(entry.modelData, 1.2) : entry.modelData
                    border.width: colorButton.selected || colorButton.activeFocus ? 2 : 1
                    border.color: colorButton.activeFocus || colorButton.hovered ? Theme.text : colorButton.selected ? Theme.accent : Theme.border
                }
                HoverHandler {
                    enabled: colorButton.enabled
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            colorButton.clicked();
                        } else if (mouse.button === Qt.RightButton) {
                            const position = swatchMouse.mapToItem(root, mouse.x, mouse.y);
                            removeAction.x = Math.min(position.x, root.width - removeAction.width);
                            removeAction.y = Math.max(0, Math.min(position.y, root.height - removeAction.height));
                            root.removalColor = entry.modelData;
                        }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: root.colors.length === 0
            text: "No presets yet"
            color: Theme.textMuted
            font.family: Theme.font
            font.pixelSize: 13
        }
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            implicitWidth: 3
            policy: Controls.ScrollBar.AsNeeded
            visible: grid.contentHeight > grid.height
            contentItem: Rectangle {
                color: Theme.textMuted
                radius: 2
            }
            background: Rectangle {
                color: Theme.border
                radius: 2
            }
        }
    }
    ActionButton {
        id: removeAction
        objectName: "calendarRemoveColorPreset"
        visible: root.opened && root.removalColor.length > 0
        width: implicitWidth
        height: implicitHeight
        z: 1
        label: "Remove preset"
        destructive: true
        Accessible.role: Accessible.MenuItem
        Accessible.name: label
        Accessible.onPressAction: clicked()
        onClicked: {
            const color = root.removalColor;
            root.removalColor = "";
            if (root.enabled && root.colors.includes(color))
                root.colorRemovalRequested(color);
            grid.forceActiveFocus();
        }
    }
}
