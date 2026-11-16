pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root

    property bool enabled: false
    property var node: null
    readonly property var audio: root.node?.audio ?? null
    readonly property bool available: root.enabled && root.node?.ready === true && root.audio !== null && root.audio.channels.length > 0 && isFinite(root.audio.volume) && root.audio.volume >= 0
    readonly property real value: root.available ? root.audio.volume * 100 : 0
    readonly property bool muted: root.available && root.audio.muted

    function setValue(value: real): bool {
        if (!root.available || !isFinite(value))
            return false;
        // shortcut: native setters have no write acknowledgement; use checked writes if explicit rejection reporting becomes necessary.
        root.audio.volume = Math.max(0, Math.min(100, value)) / 100;
        return true;
    }

    PwObjectTracker {
        objects: root.enabled && root.node ? [root.node] : []
    }
}
