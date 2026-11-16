pragma ComponentBehavior: Bound
import QtQuick
import "../common/Theme.js" as Theme

Item {
    id: root

    property var actions: []
    property var network: null
    property var bluetooth: null
    property var vpn: null
    property var idleInhibit: null
    property var localsend: null
    property var hyprsunset: null
    property var dnd: null
    property var themeColors: Theme.colors
    signal actionRequested(int index)

    readonly property real unitWidth: (width - 12 - 18) / 4
    readonly property var cells: {
        let next = 0;
        return root.actions.map((action, actionIndex) => {
            if (action.enabled === false)
                return null;
            const presentation = action.display || (action.id === "idle-inhibit" ? "details" : "icon");
            const span = presentation === "details" ? 2 : 1;
            // Never backfill a hole with a later action from the override.
            if (next % 4 + span > 4)
                next += 4 - next % 4;
            const cell = {
                action,
                actionIndex,
                presentation,
                span,
                column: next % 4,
                row: Math.floor(next / 4)
            };
            next += span;
            return cell;
        }).filter(cell => cell !== null);
    }

    implicitHeight: cells.length ? (cells[cells.length - 1].row + 1) * 42 + 6 : 0
    height: implicitHeight
    visible: cells.length > 0

    Rectangle {
        objectName: "quickSectionBackground"
        anchors.fill: parent
        radius: Theme.radius
        color: root.themeColors.section
        border.color: root.themeColors.sectionBorder
        border.width: border.color.a > 0 ? 1 : 0
    }

    Repeater {
        model: root.cells
        delegate: QuickActionTile {
            required property var modelData
            readonly property bool backed: modelData.action.id === "network" || modelData.action.id === "bluetooth" || modelData.action.id === "vpn" || modelData.action.id === "idle-inhibit" || modelData.action.id === "localsend" || modelData.action.id === "hyprsunset" || modelData.action.id === "dnd"
            readonly property var backend: modelData.action.id === "network" ? root.network : modelData.action.id === "bluetooth" ? root.bluetooth : modelData.action.id === "vpn" ? root.vpn : modelData.action.id === "idle-inhibit" ? root.idleInhibit : modelData.action.id === "localsend" ? root.localsend : modelData.action.id === "hyprsunset" ? root.hyprsunset : modelData.action.id === "dnd" ? root.dnd : null
            themeColors: root.themeColors
            objectName: "quickAction" + modelData.actionIndex
            x: 6 + modelData.column * (root.unitWidth + 6)
            y: 6 + modelData.row * 42
            width: modelData.span * root.unitWidth + (modelData.span - 1) * 6
            height: 36
            glyph: modelData.action.icon
            tooltip: modelData.action.tooltip || ""
            tooltipOn: modelData.action.tooltipOn ?? null
            tooltipOff: modelData.action.tooltipOff ?? null
            statusHint: (modelData.action.id === "localsend" || modelData.action.id === "hyprsunset" || modelData.action.id === "dnd") && backend?.available !== true ? "Unavailable" : ""
            presentation: modelData.presentation
            title: modelData.action.title || tooltip
            enabled: !backed || (backend?.available === true && !(backend.actionBusy ?? backend.busy))
            toggleAction: backed || checkable
            // Backed tiles observe checked state; only previews let Button toggle it.
            checkable: !backed && modelData.action.type === "toggle"
            checked: backed ? backend?.active === true : checkable && modelData.action.active === true
            details: backed ? backend?.details || "Unavailable" : checkable ? (checked ? modelData.action.details || "On" : "Off") : modelData.action.details || ""
            Accessible.description: !backed ? "UI preview only" : [backend?.lastError, modelData.action.id === "vpn" ? backend?.activeNames : ""].filter(text => text).join("; ") || details
            iconColor: checked ? root.themeColors.onActive : root.themeColors.text
            fillColor: root.themeColors.gridTile
            hoverColor: root.themeColors.gridTileHover
            onClicked: root.actionRequested(modelData.actionIndex)
        }
    }
}
