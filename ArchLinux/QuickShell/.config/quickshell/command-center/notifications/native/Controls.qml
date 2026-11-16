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
        signal dndStateChanged(enabled: bool)

        onDndChanged: handler.dndStateChanged(handler.dnd)

        function setDnd(enabled: bool): bool {
            return root.service.setDnd(enabled);
        }

        function toggleDnd(): bool {
            return root.service.toggleDnd();
        }
    }
}
