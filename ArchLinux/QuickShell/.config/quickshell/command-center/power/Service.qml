pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var actions: []
    property string activeAction: ""
    property string lastError: ""
    // Alias reads native state immediately, including within the launch event turn.
    property alias busy: command.running

    function execute(actionId: string): bool {
        if (command.running)
            return false;
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.enabled !== true)
            return false;
        if (typeof action.command !== "string" || action.command.trim() === "" || action.command.length > 8192 || action.command.includes("\u0000")) {
            root.lastError = "No valid command configured for power action " + actionId;
            console.warn(root.lastError);
            return false;
        }
        root.lastError = "";
        root.activeAction = actionId;
        command.exec({
            command: ["/bin/sh", "-c", action.command],
            environment: {
                COMMAND_CENTER_PID: String(Quickshell.processId)
            }
        });
        return true;
    }

    Process {
        id: command
        workingDirectory: Quickshell.shellDir
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.lastError = "Power action " + root.activeAction + " failed (exit " + exitCode + ")";
                console.warn(root.lastError);
            }
            root.activeAction = "";
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: {}
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
