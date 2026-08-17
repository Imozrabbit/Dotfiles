import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import Quickshell.Wayland

Scope {
    id: root

    //--------------------------------------------------------------------------
    // Appearance and timing
    //--------------------------------------------------------------------------

    // Keep adjustable values in one place rather than scattering unexplained
    // numbers throughout the UI implementation.
    readonly property int osdWidth: 280
    readonly property int osdHeight: 48

    // How long the OSD remains visible after the most recent volume change.
    readonly property int hideDelayMs: 1000

    // Duration of the volume-fill animation.
    readonly property int animationDurationMs: 80

    readonly property int horizontalPadding: 16
    readonly property int contentSpacing: 10
    readonly property int iconSize: 24
    readonly property int troughHeight: 8

    //--------------------------------------------------------------------------
    // PipeWire state
    //--------------------------------------------------------------------------

    // The default sink may change while Quickshell is running, such as when
    // headphones are connected. Keeping it as a property makes all dependent
    // bindings update when PipeWire chooses another default output device.
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink?.audio ?? null

    // PipeWire represents volume as a multiplier:
    //
    //     0.00 =   0%
    //     0.50 =  50%
    //     1.00 = 100%
    //     1.25 = 125%
    //
    // Volume is therefore not guaranteed to remain between 0 and 1.
    readonly property real volume: root.audio?.volume ?? 0.0
    readonly property bool muted: root.audio?.muted ?? false
    readonly property int volumePercent: Math.round(root.volume * 100)

    // Clamp only the graphical fill between 0% and 100%.
    //
    // This fixes the original bug: when PipeWire volume exceeds 100%, the fill
    // remains inside the trough instead of becoming wider than its parent.
    //
    // The real PipeWire volume is not modified. A volume of 125% still appears
    // as "125%" in the percentage label, while the bar remains visually full.
    readonly property real displayedVolume: root.muted ? 0.0 : Math.max(0.0, Math.min(root.volume, 1.0))

    // Select an appropriate icon for the current volume level.
    //
    // Quickshell.iconPath() searches the active system icon theme. This avoids
    // hard-coding a path containing your username and a specific icon theme.
    readonly property string volumeIcon: {
        if (root.muted || root.volume <= 0.0)
            return "audio-volume-muted-symbolic";

        if (root.volume < 0.34)
            return "audio-volume-low-symbolic";

        if (root.volume < 0.67)
            return "audio-volume-medium-symbolic";

        return "audio-volume-high-symbolic";
    }

    //--------------------------------------------------------------------------
    // OSD visibility
    //--------------------------------------------------------------------------

    property bool shouldShowOsd: false

    // All audio changes use the same function to reveal the OSD.
    //
    // restart() resets the countdown on every key press, so repeatedly changing
    // the volume keeps the OSD visible until the user stops.
    function revealOsd(): void {
        root.shouldShowOsd = true;
        hideTimer.restart();
    }

    // PipeWire objects are lazy. Tracking the default sink ensures that
    // Quickshell receives live updates to its volume and mute properties.
    //
    // Use an empty list when no default sink is currently available.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // Listen for changes on the current default sink's audio interface.
    //
    // Because target uses root.audio, the Connections object automatically
    // follows a new audio object when the default sink changes.
    Connections {
        target: root.audio
        ignoreUnknownSignals: true

        function onVolumeChanged(): void {
            root.revealOsd();
        }

        function onMutedChanged(): void {
            root.revealOsd();
        }
    }

    Timer {
        id: hideTimer

        interval: root.hideDelayMs
        repeat: false

        onTriggered: root.shouldShowOsd = false
    }

    //--------------------------------------------------------------------------
    // OSD window
    //--------------------------------------------------------------------------

    // LazyLoader creates the layer-shell window only while the OSD is needed.
    // Once the timer expires, the window is destroyed rather than remaining as
    // an invisible surface.
    LazyLoader {
        active: root.shouldShowOsd

        PanelWindow {
            id: osdWindow

            // This namespace helps compositors and debugging tools identify the
            // layer-shell surface.
            WlrLayershell.namespace: "volume-osd"

            // Only the bottom edge is anchored, so the compositor places the OSD
            // horizontally in the center.
            anchors.bottom: true

            // Scale the bottom margin based on the monitor's height.
            margins.bottom: Math.round(screen.height / 30)

            // Do not reserve desktop space. Normal windows may occupy the area
            // underneath the temporary OSD.
            exclusiveZone: 0

            implicitWidth: root.osdWidth
            implicitHeight: root.osdHeight
            color: "transparent"

            // An empty input region makes the entire OSD click-through.
            // It will never intercept mouse input intended for another window.
            mask: Region {}

            // Main rounded OSD background.
            Rectangle {
                anchors.fill: parent

                radius: height / 2
                color: "#4d2c2c2c"

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: root.horizontalPadding
                        rightMargin: root.horizontalPadding
                    }

                    spacing: root.contentSpacing

                    //------------------------------------------------------------------
                    // Volume icon
                    //------------------------------------------------------------------

                    IconImage {
                        Layout.alignment: Qt.AlignVCenter

                        implicitSize: root.iconSize
                        source: Quickshell.iconPath(root.volumeIcon)
                    }

                    //------------------------------------------------------------------
                    // Volume trough
                    //------------------------------------------------------------------

                    Rectangle {
                        id: volumeTrough

                        // Consume all horizontal space not used by the icon and
                        // percentage label.
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.troughHeight
                        Layout.alignment: Qt.AlignVCenter

                        radius: height / 2
                        color: "#33ffffff"

                        // This is an additional safety boundary.
                        //
                        // Even if the fill width is accidentally calculated as
                        // larger than the trough in the future, clip prevents the
                        // child from being painted outside the trough.
                        clip: true

                        //----------------------------------------------------------------
                        // Filled portion
                        //----------------------------------------------------------------

                        Rectangle {
                            id: volumeFill

                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }

                            // Use width rather than implicitWidth.
                            //
                            // width controls the item's actual geometry.
                            // implicitWidth only reports a preferred size and is
                            // not the right property for this progress indicator.
                            width: parent.width * root.displayedVolume

                            radius: parent.radius
                            color: "#ffffffff"

                            // Smoothly animate between volume levels rather than
                            // jumping immediately to the new width.
                            Behavior on width {
                                NumberAnimation {
                                    duration: root.animationDurationMs
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    //------------------------------------------------------------------
                    // Percentage label
                    //------------------------------------------------------------------

                    // The bar is visually capped at 100%, but this label still
                    // exposes the real PipeWire value when amplification is used.
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 42

                        text: root.muted ? "Muted" : root.volumePercent + "%"

                        color: "#ffffffff"
                        font.pixelSize: 13

                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
