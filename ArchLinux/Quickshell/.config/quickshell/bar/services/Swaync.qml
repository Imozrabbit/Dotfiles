import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool dnd: false
    property bool hasNotifications: false
    property int retryDelay: 2000

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
                    if (!status || typeof status !== "object" || (typeof status.class !== "string" && typeof status.alt !== "string"))
                        return;
                    const marker = String(status.class ?? "") + " " + String(status.alt ?? "");
                    root.dnd = marker.indexOf("dnd-") !== -1;
                    root.hasNotifications = marker.indexOf("notification") !== -1;
                    root.retryDelay = 2000;
                } catch (error) {
                    // Keep the last valid state when SwayNC emits malformed output.
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                restartTimer.interval = root.retryDelay;
                root.retryDelay = Math.min(root.retryDelay * 2, 10000);
                restartTimer.restart();
            }
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
