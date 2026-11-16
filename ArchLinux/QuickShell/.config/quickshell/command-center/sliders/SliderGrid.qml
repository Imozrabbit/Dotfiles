pragma ComponentBehavior: Bound
import QtQuick
import "../common/Theme.js" as Theme

Item {
    id: root

    property var sliders: []
    property var themeColors: Theme.colors
    property var volumeControl: null
    property var microphoneControl: null
    property var brightnessControl: null
    readonly property real volume: root.volumeControl?.value ?? 0
    readonly property real microphoneVolume: root.microphoneControl?.value ?? 0
    readonly property real brightness: root.brightnessControl?.value ?? 1

    readonly property real unitWidth: Math.max(0, (width - 6) / 2)
    readonly property var cells: {
        let next = 0;
        return root.sliders.filter(slider => slider.enabled !== false).map(slider => {
            const span = slider.length;
            // Keep override order; never backfill a hole before a full-width slider.
            if (next % 2 + span > 2)
                next += 2 - next % 2;
            const cell = {
                slider,
                span,
                column: next % 2,
                row: Math.floor(next / 2)
            };
            next += span;
            return cell;
        });
    }

    implicitHeight: cells.length ? (cells[cells.length - 1].row + 1) * 38 - 6 : 0
    height: implicitHeight
    visible: cells.length > 0

    function controlFor(type: string): var {
        return type === "volume" ? root.volumeControl : type === "microphone" ? root.microphoneControl : root.brightnessControl;
    }

    Repeater {
        model: root.cells
        delegate: SliderControl {
            id: control
            required property var modelData
            required property int index
            objectName: "sliderControl" + index
            sliderType: modelData.slider.type
            readonly property var backend: root.controlFor(sliderType)
            themeColors: root.themeColors
            x: modelData.column * (root.unitWidth + 6)
            y: modelData.row * 38
            width: modelData.span * root.unitWidth + (modelData.span - 1) * 6
            available: !!backend && backend.available
            monitors: sliderType === "brightness" ? backend?.monitors ?? [] : []
            selectedMonitorId: backend?.selectedId ?? ""
            targetKey: backend?.targetKey ?? ""
            value: backend?.displayValue ?? backend?.value ?? (sliderType === "brightness" ? 1 : 0)
            description: {
                const status = !available ? "Unavailable" : Math.round(backend.displayValue ?? backend.value) + "%" + (backend.updating ? " (updating)" : backend.muted ? " (muted)" : "");
                const details = backend?.lastError ? (!available ? status + ". " : "") + backend.lastError : status;
                return backend?.selectedLabel ? backend.selectedLabel + ". " + details : details;
            }
            onValueRequested: value => {
                if (backend && backend.available)
                    backend.setValue(value);
            }
            onMonitorRequested: id => {
                if (backend && sliderType === "brightness")
                    backend.selectMonitor(id);
            }
        }
    }
}
