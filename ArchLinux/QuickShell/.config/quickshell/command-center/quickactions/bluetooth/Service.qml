pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

Scope {
    id: root

    property bool enabled: false
    // Installed qmltypes omit ObjectModel.values; native fixture verifies it.
    // qmllint disable missing-property
    property var adapters: root.enabled ? Bluetooth.adapters.values : []
    // qmllint enable missing-property
    readonly property var powered: root.adapters.map(adapter => adapter.enabled)
    readonly property bool available: root.enabled && root.adapters.length > 0
    readonly property bool active: root.available && root.powered.some(value => value)
    readonly property bool blocked: root.adapters.some(adapter => adapter.state === BluetoothAdapterState.Blocked) || /rfkill|blocked/i.test(root.lastError)
    readonly property string details: !root.available ? "Unavailable" : root.active ? (root.powered.every(value => value) ? "On" : "Mixed") : root.blocked ? "Blocked" : "Off"
    property bool busy: false
    property string lastError: ""

    property var requestAdapters: []
    property int nextAdapter: 0
    property bool target: false
    property int resultCode: -1
    property string commandError: ""

    onPoweredChanged: {
        if (!root.busy)
            root.lastError = "";
    }
    onAdaptersChanged: {
        root.lastError = "";
        if (root.adapters.length === 0)
            root.requestAdapters = [];
    }

    function toggle(): bool {
        if (root.busy || !root.enabled || root.adapters.length === 0)
            return false;
        root.target = !root.adapters.some(adapter => adapter.enabled);
        // BlueZ can reuse controller paths; retain original QObject identities.
        root.requestAdapters = root.adapters.map(adapter => adapter);
        root.nextAdapter = 0;
        root.lastError = "";
        root.busy = true;
        root.startNext();
        return true;
    }

    function startNext(): void {
        while (root.nextAdapter < root.requestAdapters.length) {
            const adapter = root.requestAdapters[root.nextAdapter++];
            if (!adapter || !root.adapters.includes(adapter))
                continue;
            root.resultCode = -1;
            root.commandError = "";
            // Native enabled writes are optimistic; let BlueZ report Powered instead.
            command.exec({
                command: ["busctl", "--system", "--timeout=5s", "set-property", "org.bluez", adapter.dbusPath, "org.bluez.Adapter1", "Powered", "b", root.target ? "true" : "false"],
                environment: {
                    LC_ALL: "C"
                }
            });
            return;
        }
        root.requestAdapters = [];
        root.busy = false;
    }

    function finishCommand(): void {
        if (!root.busy)
            return;
        if (root.resultCode !== 0) {
            const error = root.commandError.trim() || "Bluetooth power request failed (exit " + root.resultCode + ")";
            console.warn(error);
            if (root.adapters.includes(root.requestAdapters[root.nextAdapter - 1]))
                root.lastError = error;
        }
        root.startNext();
    }

    Process {
        id: command
        onExited: (exitCode, exitStatus) => {
            root.resultCode = exitStatus === 0 ? exitCode : -1;
        }
        onRunningChanged: {
            // Failed starts have no exited signal; defer until normal exit data is drained.
            if (!running && root.busy)
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: {}
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.commandError = (root.commandError + data).slice(-1024)
        }
    }
}
