pragma ComponentBehavior: Bound
import QtQml

QtObject {
    id: root
    property bool enabled: false
    property var controller: null
    readonly property bool available: root.enabled && typeof root.controller?.dnd === "boolean" && typeof root.controller?.toggleDnd === "function"
    readonly property bool active: root.available && root.controller.dnd
    readonly property bool busy: false
    readonly property string details: !root.available ? "Unavailable" : root.active ? "On" : "Off"
    readonly property string lastError: ""

    function toggle(): bool {
        if (!root.available)
            return false;
        root.controller.toggleDnd();
        return true;
    }
}
