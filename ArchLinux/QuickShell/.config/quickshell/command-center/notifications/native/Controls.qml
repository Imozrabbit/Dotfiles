pragma ComponentBehavior: Bound
import QtQml
import Quickshell.Io

QtObject {
    id: root
    required property Service service

    readonly property IpcHandler ipc: IpcHandler {
        id: handler
        target: "notifications"
        readonly property bool dnd: root.service.dnd
        readonly property bool hasHistory: root.service.entries.length > 0
        signal dndStateChanged(enabled: bool)
        signal historyStateChanged(present: bool)

        onDndChanged: handler.dndStateChanged(handler.dnd)
        onHasHistoryChanged: handler.historyStateChanged(handler.hasHistory)

        function setDnd(enabled: bool): bool {
            return root.service.setDnd(enabled);
        }

        function toggleDnd(): bool {
            return root.service.toggleDnd();
        }
    }
}
