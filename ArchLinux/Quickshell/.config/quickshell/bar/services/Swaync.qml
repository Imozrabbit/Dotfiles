import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool dnd: false
    property bool hasNotifications: false

    function openPanel() {
        Quickshell.execDetached(["swaync-client", "--open-panel"]);
    }

    Process {
        id: subscription

        command: ["swaync-client", "--subscribe-waybar"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                try {
                    const status = JSON.parse(data);
                    const marker = String(status.class ?? "") + " " + String(status.alt ?? "");
                    root.dnd = marker.indexOf("dnd-") !== -1;
                    root.hasNotifications = marker.indexOf("notification") !== -1;
                } catch (error) {
                    // Keep the last valid state when SwayNC emits malformed output.
                }
            }
        }

        onRunningChanged: {
            if (!running)
                restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer

        interval: 2000
        repeat: false
        onTriggered: {
            if (!subscription.running)
                subscription.running = true;
        }
    }
}
