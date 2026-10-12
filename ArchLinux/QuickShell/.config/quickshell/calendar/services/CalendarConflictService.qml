import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string helperPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper"
    readonly property string brokerPath: Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/conflict-broker.sh"
    readonly property string personalDirectory: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/calendars/personal"
    readonly property string personalCache: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/calendars/personal.sync.json"
    readonly property string statePath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME");
        return (stateHome && stateHome.length > 0 ? stateHome : Quickshell.env("HOME") + "/.local/state") + "/quickshell-calendar/conflicts.json";
    }
    property var conflicts: []
    property bool stateValid: false
    property string errorMessage: ""
    property string pendingUid: ""
    property string pendingRevision: ""
    property var pendingResolveCommand: []
    property bool busy: false
    readonly property bool hasConflict: root.conflicts.length > 0
    readonly property var currentConflict: root.conflicts.length > 0 ? root.conflicts[0] : null

    function isConflicted(uid) {
        if (uid && typeof uid === "object")
            uid = uid.masterUid || uid.sourceUid || uid.uid;
        const sourceUid = String(uid).replace(/^.*?:/, "");
        return root.conflicts.some(conflict => conflict.uid === uid || conflict.uid === sourceUid || (conflict.kind === "group" && conflict.members.some(member => member.uid === uid || member.uid === sourceUid)));
    }

    function loadState(text) {
        try {
            const state = JSON.parse(text);
            const object = value => value && typeof value === "object" && !Array.isArray(value);
            const keys = (value, expected) => object(value) && Object.keys(value).length === expected.length && expected.every(key => Object.prototype.hasOwnProperty.call(value, key));
            const hash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
            const identities = new Set();
            function valid(conflict) {
                if (!object(conflict) || typeof conflict.uid !== "string" || conflict.uid.length === 0 || identities.has(conflict.uid) || !object(conflict.local) || !object(conflict.remote) || typeof conflict.localIcs !== "string" || typeof conflict.remoteIcs !== "string" || !["", "local", "remote"].includes(conflict.choice))
                    return false;
                identities.add(conflict.uid);
                if (conflict.kind !== "group")
                    return keys(conflict, ["uid", "local", "remote", "localIcs", "remoteIcs", "choice"]);
                if (state.version !== 2 || !keys(conflict, ["uid", "kind", "version", "local", "remote", "localIcs", "remoteIcs", "choice", "revision", "members", "ready", "problem"]) || conflict.version !== 1 || !hash(conflict.revision) || typeof conflict.ready !== "boolean" || typeof conflict.problem !== "string" || (conflict.ready ? conflict.problem.length !== 0 : conflict.problem.length === 0 || conflict.choice !== "") || !Array.isArray(conflict.members) || conflict.members.length === 0 || conflict.members.length > 366)
                    return false;
                const local = JSON.parse(conflict.localIcs);
                const remote = JSON.parse(conflict.remoteIcs);
                if (!Array.isArray(local) || !Array.isArray(remote) || local.length !== conflict.members.length || remote.length !== conflict.members.length)
                    return false;
                const members = new Set();
                return conflict.members.every((member, index) => {
                    if (!keys(member, ["uid", "localIcs", "remoteIcs", "localRevision", "remoteRevision"]) || typeof member.uid !== "string" || member.uid.length === 0 || members.has(member.uid) || typeof member.localIcs !== "string" || typeof member.remoteIcs !== "string" || !hash(member.localRevision) || !hash(member.remoteRevision))
                        return false;
                    members.add(member.uid);
                    return keys(local[index], ["uid", "ical"]) && keys(remote[index], ["uid", "ical"]) && local[index].uid === member.uid && remote[index].uid === member.uid && local[index].ical === member.localIcs && remote[index].ical === member.remoteIcs;
                });
            }
            if (text.length > 616 * 1024 * 1024 || !keys(state, ["version", "conflicts"]) || ![1, 2].includes(state.version) || !Array.isArray(state.conflicts) || !state.conflicts.every(valid))
                throw new Error("Unsupported conflict state");
            root.conflicts = state.conflicts;
            root.stateValid = true;
            root.errorMessage = "";
        } catch (error) {
            root.stateValid = false;
            root.errorMessage = "Could not read calendar conflict state";
        }
    }

    function choose(side, reviewedUid, reviewedRevision) {
        if (!root.stateValid || !root.currentConflict || root.busy || (side !== "local" && side !== "remote"))
            return;
        const grouped = root.currentConflict.kind === "group";
        if (grouped && (!root.currentConflict.ready || root.currentConflict.uid !== reviewedUid || root.currentConflict.revision !== reviewedRevision)) {
            root.errorMessage = root.currentConflict.problem || "Whole-series conflict resolution required";
            return;
        }
        root.pendingUid = root.currentConflict.uid;
        root.pendingRevision = grouped ? reviewedRevision : "";
        root.pendingResolveCommand = grouped
            ? [root.brokerPath, "resolve-group", root.personalDirectory, root.personalCache, "personal", root.statePath, root.pendingUid, root.pendingRevision]
            : [root.brokerPath, "resolve", "personal", root.statePath, root.pendingUid];
        root.busy = true;
        selectProcess.command = grouped ? [root.helperPath, "conflict-group-select", root.statePath, root.pendingUid, side, root.pendingRevision]
            : [root.helperPath, "conflict-select", root.statePath, root.pendingUid, side];
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
            resolveProcess.command = root.pendingResolveCommand;
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
            if (exitCode === 2 && root.pendingRevision.length > 0) {
                root.busy = false;
                root.stateFile.reload();
                root.pendingUid = "";
                root.errorMessage = "Series resolved, but calendar cache could not refresh. Do not retry this resolution.";
                return;
            }
            if (exitCode === 4) {
                root.busy = false;
                root.stateFile.reload();
                root.errorMessage = "Series resolution needs resource review; pimsync remains paused. Do not retry this resolution.";
                return;
            }
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
