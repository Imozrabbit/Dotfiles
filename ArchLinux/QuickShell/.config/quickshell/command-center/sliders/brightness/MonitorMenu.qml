pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQml.Models
import "../../components/menus"

ContextMenu {
    id: root

    property var monitors: []
    property string selectedId: ""
    signal monitorRequested(string id)

    objectName: "brightnessMonitorMenu"
    width: Math.min(280, Math.max(0, (root.parent?.Window.window?.width ?? 292) - 12))
    onMonitorsChanged: {
        if (root.monitors.length === 0)
            root.close();
    }

    Instantiator {
        model: root.monitors
        delegate: ContextMenuItem {
            required property var modelData
            required property int index
            objectName: "brightnessMonitor" + index
            themeColors: root.themeColors
            text: modelData.label
            glyph: modelData.id === root.selectedId ? "󰄬" : " "
            Accessible.description: modelData.id === root.selectedId ? "Selected monitor" : ""
            onTriggered: root.monitorRequested(modelData.id)
        }
        onObjectAdded: (index, object) => root.insertItem(index, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }
}
