import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

Scope {
    id: root

    readonly property int osdWidth: 280
    readonly property int osdHeight: 40
    readonly property int stackSpacing: 8
    readonly property int hideDelayMs: 1000

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink?.audio ?? null
    readonly property real volume: root.audio?.volume ?? 0
    readonly property bool muted: root.audio?.muted ?? false
    readonly property int volumePercent: Math.round(root.volume * 100)
    readonly property real displayedVolume: root.muted ? 0 : Math.max(0, Math.min(root.volume, 1))
    readonly property string volumeIcon: {
        if (root.muted || root.volume <= 0)
            return "audio-volume-muted-symbolic";
        if (root.volume < 0.34)
            return "audio-volume-low-symbolic";
        if (root.volume < 0.67)
            return "audio-volume-medium-symbolic";
        return "audio-volume-high-symbolic";
    }

    // Host-specific backlight path. Find another laptop's device with:
    // ls /sys/class/backlight/*/brightness
    readonly property string backlightPath: "/sys/class/backlight/amdgpu_bl1"
    property int rawBrightness: -1
    property int maxBrightness: -1
    property int lastBrightness: -1
    property int brightnessPercent: -1
    property bool brightnessInitialized: false
    readonly property real displayedBrightness: root.brightnessPercent < 0 ? 0 : Math.max(0, Math.min(root.brightnessPercent / 100, 1))

    property bool volumeVisible: false
    property bool brightnessVisible: false
    readonly property int visibleRows: (root.volumeVisible ? 1 : 0) + (root.brightnessVisible ? 1 : 0)
    readonly property int stackHeight: root.visibleRows * root.osdHeight + Math.max(0, root.visibleRows - 1) * root.stackSpacing

    function revealVolume(): void {
        root.volumeVisible = true;
        volumeHideTimer.restart();
    }

    function revealBrightness(): void {
        root.brightnessVisible = true;
        brightnessHideTimer.restart();
    }

    function updateBrightness(): void {
        if (root.rawBrightness < 0 || root.maxBrightness <= 0 || root.rawBrightness > root.maxBrightness)
            return;

        const nextPercent = Math.round(root.rawBrightness * 100 / root.maxBrightness);
        if (!root.brightnessInitialized) {
            root.brightnessInitialized = true;
            root.lastBrightness = root.rawBrightness;
            root.brightnessPercent = nextPercent;
            return;
        }

        root.brightnessPercent = nextPercent;
        if (root.rawBrightness === root.lastBrightness)
            return;

        root.lastBrightness = root.rawBrightness;
        root.revealBrightness();
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    Connections {
        target: root.audio
        ignoreUnknownSignals: true

        function onVolumeChanged(): void {
            root.revealVolume();
        }

        function onMutedChanged(): void {
            root.revealVolume();
        }
    }

    FileView {
        id: maxBrightnessFile

        path: root.backlightPath + "/max_brightness"
        onLoaded: {
            const text = maxBrightnessFile.text().trim();
            const value = text === "" ? NaN : Number(text);
            root.maxBrightness = isFinite(value) && value > 0 ? Math.round(value) : -1;
            root.updateBrightness();
        }
        onLoadFailed: root.maxBrightness = -1
    }

    FileView {
        id: brightnessFile

        path: root.backlightPath + "/brightness"
        onLoaded: {
            const text = brightnessFile.text().trim();
            const value = text === "" ? NaN : Number(text);
            root.rawBrightness = isFinite(value) && value >= 0 ? Math.round(value) : -1;
            root.updateBrightness();
        }
        onLoadFailed: root.rawBrightness = -1
    }

    Process {
        id: brightnessWatcher

        command: ["inotifywait", "--monitor", "--quiet", "--event", "modify", "--format", "%e", root.backlightPath + "/brightness"]
        running: true
        stdout: SplitParser {
            onRead: brightnessFile.reload()
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!brightnessWatcher.running)
                brightnessWatcher.running = true;
            if (root.maxBrightness < 0)
                maxBrightnessFile.reload();
            brightnessFile.reload();
        }
    }

    Component.onCompleted: {
        maxBrightnessFile.reload();
        brightnessFile.reload();
    }

    Timer {
        id: volumeHideTimer

        interval: root.hideDelayMs
        repeat: false
        onTriggered: root.volumeVisible = false
    }

    Timer {
        id: brightnessHideTimer

        interval: root.hideDelayMs
        repeat: false
        onTriggered: root.brightnessVisible = false
    }

    LazyLoader {
        active: root.visibleRows > 0

        PanelWindow {
            id: osdWindow

            WlrLayershell.namespace: "level-osd"
            anchors.bottom: true
            margins.bottom: root.visibleRows > 1 ? Math.max(0, Math.round(screen.height / 30) - root.osdHeight - root.stackSpacing) : Math.round(screen.height / 30)
            exclusiveZone: 0
            implicitWidth: root.osdWidth
            implicitHeight: root.stackHeight
            color: "transparent"
            mask: Region {}

            ColumnLayout {
                anchors.fill: parent
                spacing: root.stackSpacing

                OsdItem {
                    visible: root.volumeVisible
                    Layout.preferredWidth: root.osdWidth
                    Layout.preferredHeight: root.osdHeight
                    iconName: root.volumeIcon
                    fillLevel: root.displayedVolume
                    label: root.muted ? "Muted" : root.volumePercent + "%"
                }

                OsdItem {
                    visible: root.brightnessVisible
                    Layout.preferredWidth: root.osdWidth
                    Layout.preferredHeight: root.osdHeight
                    iconName: "display-brightness-symbolic"
                    fillLevel: root.displayedBrightness
                    label: root.brightnessPercent >= 0 ? root.brightnessPercent + "%" : "N/A"
                }
            }
        }
    }
}
