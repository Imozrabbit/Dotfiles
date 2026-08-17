import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink?.audio ?? null

    readonly property bool available: root.audio !== null
    readonly property real volume: root.audio?.volume ?? 0.0
    readonly property bool muted: root.audio?.muted ?? false

    function setVolume(value) {
        if (!root.audio)
            return;

        root.audio.volume = Math.max(0.0, Math.min(1.0, value));
    }

    function toggleMute() {
        if (root.audio)
            root.audio.muted = !root.audio.muted;
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
}
