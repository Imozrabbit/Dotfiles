import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string helperPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper"
    readonly property string brokerPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/conflict-broker.sh"
    readonly property string statePath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME");
        return (stateHome && stateHome.length > 0 ? stateHome : Quickshell.env("HOME") + "/.local/state") + "/quickshell-calendar/conflicts.json";
    }
    property var conflicts: []
    property bool stateValid: false
    property string errorMessage: ""
    property string pendingUid: ""
    property bool busy: false
    readonly property bool hasConflict: root.conflicts.length > 0
    readonly property var currentConflict: root.conflicts.length > 0 ? root.conflicts[0] : null

    function isConflicted(uid) {
        return root.conflicts.some(conflict => conflict.uid === uid || conflict.uid === String(uid).replace(/^.*?:/, ""));
    }

    function loadState(text) {
        try {
            const state = JSON.parse(text);
            if (!state || state.version !== 1 || !Array.isArray(state.conflicts) || state.conflicts.some(conflict => !conflict || typeof conflict.uid !== "string" || conflict.uid.length === 0 || !conflict.local || typeof conflict.local !== "object" || Array.isArray(conflict.local) || !conflict.remote || typeof conflict.remote !== "object" || Array.isArray(conflict.remote) || typeof conflict.localIcs !== "string" || typeof conflict.remoteIcs !== "string" || !["", "local", "remote"].includes(conflict.choice)))
                throw new Error("Unsupported conflict state");
            root.conflicts = state.conflicts;
            root.stateValid = true;
            root.errorMessage = "";
        } catch (error) {
            root.stateValid = false;
            root.errorMessage = "Could not read calendar conflict state";
        }
    }

    function choose(side) {
        if (!root.stateValid || !root.currentConflict || root.busy || (side !== "local" && side !== "remote"))
            return;
        root.pendingUid = root.currentConflict.uid;
        root.busy = true;
        selectProcess.command = [root.helperPath, "conflict-select", root.statePath, root.pendingUid, side];
        selectProcess.running = true;
    }

    property FileView stateFile: FileView {
        path: root.statePath
        preload: true
        watchChanges: true
        onLoaded: root.loadState(text())
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound && root.conflicts.length === 0) {
                root.conflicts = [];
                root.stateValid = true;
                root.errorMessage = "";
            } else {
                root.stateValid = false;
                root.errorMessage = "Could not read calendar conflict state";
            }
        }
    }

    property Process selectProcess: Process {
        id: selectProcess
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.busy = false;
                root.errorMessage = "Could not select conflict version";
                return;
            }
            resolveProcess.command = [root.brokerPath, "resolve", "personal", root.statePath, root.pendingUid];
            resolveProcess.running = true;
        }
        // qmllint enable signal-handler-parameters
    }

    property Process resolveProcess: Process {
        id: resolveProcess
        stderr: StdioCollector {
            id: resolveStderr
        }
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 3) {
                root.busy = false;
                root.stateFile.reload();
                root.pendingUid = "";
                root.errorMessage = "Conflict resolved, but pimsync could not restart";
                return;
            }
            if (exitCode !== 0) {
                root.busy = false;
                root.errorMessage = "Could not resolve calendar conflict";
                return;
            }
            if (resolveStderr.text.indexOf("412") >= 0 || resolveStderr.text.indexOf("Error uploading resolved item") >= 0) {
                root.busy = false;
                root.errorMessage = "Remote event changed during resolution; reopen conflict";
                root.stateFile.reload();
                return;
            }
            root.busy = false;
            root.stateFile.reload();
            root.pendingUid = "";
        }
        // qmllint enable signal-handler-parameters
    }
}
