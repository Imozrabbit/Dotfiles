pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "ddc" as Ddc

Scope {
    id: root

    property bool enabled: false
    property bool panelOpen: false
    property var outputs: []
    readonly property bool live: root.enabled && root.panelOpen
    property string selectedId: ""
    property string lastSelectedLabel: ""
    property bool awaitingDiscovery: false
    property int opening: 0
    property var requestedValue: null
    readonly property var internalOutputs: root.outputs.filter(name => /^(eDP|LVDS|DSI)-/.test(name))
    readonly property bool hasExternalOutputs: root.outputs.some(name => !root.internalOutputs.includes(name))
    readonly property var monitors: root.outputs.map(name => {
        // shortcut: one internal panel; map sysfs devices explicitly if multi-panel laptops are needed.
        if (root.internalOutputs.length === 1 && root.internalOutputs[0] === name)
            return {
                id: "backlight:" + name,
                connector: name,
                label: "Built-in (" + name + ")",
                kind: "backlight"
            };
        const display = ddc.monitors.find(display => display.connector === name);
        return display ? Object.assign({}, display, {
            kind: "ddc"
        }) : null;
    }).filter(monitor => monitor !== null)
    readonly property var selected: root.monitors.find(monitor => monitor.id === root.selectedId) ?? null
    readonly property var backend: root.selected?.kind === "backlight" ? backlight : root.selected?.kind === "ddc" ? ddc : null
    readonly property bool available: root.live && !!root.backend && root.backend.available && (!root.awaitingDiscovery || root.selected.kind === "backlight")
    readonly property real value: root.backend?.value ?? 1
    readonly property real displayValue: root.requestedValue ?? root.value
    readonly property bool updating: root.requestedValue !== null
    readonly property bool backendBusy: root.backend?.busy ?? false
    readonly property bool busy: root.live && (root.awaitingDiscovery || ddc.busy || root.backendBusy)
    readonly property string lastError: root.backend ? root.backend.lastError : ddc.lastError || (root.selectedId !== "" ? "Selected monitor unavailable" : "No controllable monitors")
    readonly property string selectedLabel: root.selected?.label ?? root.lastSelectedLabel
    readonly property string targetKey: root.selected ? root.selected.id + ":" + (root.selected.bus ?? backlight.device) + ":" + root.opening : ""

    function initializeSelection(): void {
        if (root.live && root.selectedId === "")
            root.selectedId = root.monitors[0]?.id ?? "";
    }

    function refreshSelection(): void {
        ++root.opening;
        root.awaitingDiscovery = root.hasExternalOutputs;
        if (!root.awaitingDiscovery)
            root.initializeSelection();
        ddc.discover();
    }

    function selectMonitor(id: string): bool {
        if (!root.live || !root.monitors.some(monitor => monitor.id === id))
            return false;
        root.awaitingDiscovery = false;
        root.selectedId = id;
        root.refresh();
        return true;
    }

    function setValue(value: real): bool {
        if (!root.available || !isFinite(value) || !root.backend.setValue(value))
            return false;
        root.requestedValue = Math.max(1, Math.min(100, value));
        return true;
    }

    function settleFeedback(): void {
        if (root && !root.backendBusy)
            root.requestedValue = null;
    }

    function refresh(): void {
        if (root.live && root.backend)
            root.backend.refresh();
    }

    function discover(): void {
        ddc.discover();
    }

    onMonitorsChanged: {
        if (!root.hasExternalOutputs) {
            root.awaitingDiscovery = false;
            root.initializeSelection();
        }
    }
    onSelectedChanged: {
        if (root.selected)
            root.lastSelectedLabel = root.selected.label;
    }
    onTargetKeyChanged: root.requestedValue = null
    onLastErrorChanged: {
        if (root.lastError !== "")
            root.requestedValue = null;
    }
    onBackendBusyChanged: {
        if (!root.backendBusy)
            Qt.callLater(root.settleFeedback);
    }
    onLiveChanged: {
        if (root.live)
            root.refreshSelection();
        else {
            root.awaitingDiscovery = false;
            root.requestedValue = null;
        }
    }
    Component.onCompleted: {
        if (root.live)
            root.refreshSelection();
    }

    Service {
        id: backlight
        enabled: root.live && root.selected?.kind === "backlight"
    }
    Ddc.Service {
        id: ddc
        enabled: root.live && root.hasExternalOutputs
        outputs: root.outputs
        targetId: root.selected?.kind === "ddc" ? root.selectedId : ""
        onDiscoveryFinished: {
            root.awaitingDiscovery = false;
            root.initializeSelection();
        }
    }
}
