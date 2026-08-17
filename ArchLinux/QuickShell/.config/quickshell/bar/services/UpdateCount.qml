import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int updateCount: 0
    property int pendingCount: 0
    readonly property bool checking: updateProcess.running

    function refresh() {
        if (updateProcess.running)
            return;

        root.pendingCount = 0;
        updateProcess.running = true;
    }

    Process {
        id: updateProcess

        command: ["sh", "-c", "updates=$(checkupdates); status=$?; if [ \"$status\" -eq 0 ] || [ \"$status\" -eq 2 ]; then printf '%s\\n' \"$updates\"; printf '__CHECKUPDATES_OK__\\n'; fi"]

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line === "__CHECKUPDATES_OK__") {
                    root.updateCount = root.pendingCount;
                } else if (line !== "") {
                    root.pendingCount++;
                }
            }
        }
    }

    Timer {
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
