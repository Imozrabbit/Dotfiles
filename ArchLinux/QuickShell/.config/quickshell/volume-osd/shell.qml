import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import Quickshell.Wayland

Scope {
    id: root

    // Bind the pipewire node so its volume will be tracked
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio

        function onVolumeChanged() {
            root.shouldShowOsd = true;
            hideTimer.restart();
        }
        function onMutedChanged() {
            root.shouldShowOsd = true;
            hideTimer.restart();
        }
    }

    property bool shouldShowOsd: false

    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: root.shouldShowOsd = false
    }

    // The OSD window will be created and destroyed based on shouldShowOsd.
    // PanelWindow.visible could be set instead of using a loader, but using
    // a loader will reduce the memory overhead when the window isn't open.
    LazyLoader {
        active: root.shouldShowOsd

        PanelWindow {
            // Since the panel's screen is unset, it will be picked by the compositor
            // when the window is created. Most compositors pick the current active monitor.
            WlrLayershell.namespace: "volume-osd"

            anchors.bottom: true
            margins.bottom: screen.height / 30
            exclusiveZone: 0

            implicitWidth: 260
            implicitHeight: 45
            color: "transparent"

            // An empty click mask prevents the window from blocking mouse events.
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "#4d2c2c2c"

                RowLayout {
                    spacing: 6

                    anchors {
                        fill: parent
                        leftMargin: 15
                        rightMargin: 15
                    }

                    IconImage {
                        implicitSize: 25
                        source: Pipewire.defaultAudioSink?.audio.muted ? "file:///home/Zrabbit/.local/share/icons/WhiteSur-dark/status/symbolic/audio-volume-muted-symbolic.svg" : "file:///home/Zrabbit/.local/share/icons/WhiteSur-dark/status/symbolic/audio-volume-high-symbolic.svg"
                    }

                    // The fill bar
                    Rectangle {
                        // Stretches to fill all left-over space
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 20
                        color: "#33ffffff"

                        // The highlight bar
                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            implicitWidth: parent.width * (Pipewire.defaultAudioSink?.audio.volume ?? 0)
                            radius: parent.radius
                        }
                    }
                }
            }
        }
    }
}
