import QtQuick
import Quickshell
import Quickshell.Io
import "../common/ProfileMutation.js" as ProfileMutation

QtObject {
    id: root

    required property var registry
    required property string helperPath
    property string backend: "subscriptions"
    property var records: []
    property var conversions: []
    property var conflicts: []
    property bool ready: false
    property string revision: ""
    property string errorMessage: ""
    property var pending: null
    property bool reloadAgain: false
    property int serial: 0
    readonly property bool busy: root.pending !== null
    signal finished(var result)
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/pimsync/pimsync.conf"
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell-calendar/" + root.backend + "/status.json"

    function recordForId(id) {
        return root.records.find(record => record.id === id) || null;
    }

    function reload() {
        if (root.busy || listing.running) {
            root.reloadAgain = true;
            return;
        }
        root.reloadAgain = false;
        listing.running = true;
    }

    function listed(exitCode) {
        let reply;
        try {
            reply = JSON.parse(listOutput.text);
        } catch (error) {
            reply = null;
        }
        root.ready = exitCode === 0 && reply && reply.ok === true && Array.isArray(reply.records) && typeof reply.revision === "string";
        if (root.ready) {
            root.records = reply.records;
            if (root.backend === "caldav")
                root.conversions = Array.isArray(reply.conversions) ? reply.conversions : [];
            root.revision = reply.revision;
            root.errorMessage = "";
        } else {
            root.errorMessage = reply && typeof reply.message === "string" ? reply.message : "Subscription helper unavailable; settings were not changed";
        }
        if (root.reloadAgain)
            Qt.callLater(root.reload);
    }

    function start(action, id, body, draft) {
        if (root.backend === "caldav" && (action === "refresh" || action === "save") && root.conflicts.some(conflict => conflict.calendarId === id))
            return {
                ok: false,
                field: "storage",
                message: "Resolve calendar conflicts first"
            };
        if (root.busy || root.registry.importOwner || root.registry.subscriptionOwner || root.registry.localRemovalPending)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        if (!root.ready || !root.registry.ready)
            return {
                ok: false,
                field: "storage",
                message: root.errorMessage || "Calendar settings are not ready"
            };
        const conversion = root.backend === "caldav" ? root.conversions.find(session => session.id === id) : null;
        const matchingLifecycle = conversion && body?.session === conversion.session && body?.expectedRevision === conversion.revision && (conversion.kind === "local-to-synced" ? ["attach-finish", "attach-cancel", "attach-retry"].includes(action) : ["remote-delete", "local-preserve"].includes(conversion.kind) ? ["remote-delete-finish", "remote-delete-cancel", "remote-delete-retry"].includes(action) : ["convert-finish", "convert-cancel"].includes(action));
        if (conversion && !matchingLifecycle)
            return {
                ok: false,
                field: "storage",
                message: "Calendar conversion is paused. Recovery files: " + conversion.recoveryPaths.join(", ")
            };
        const token = ++root.serial;
        root.pending = {
            action,
            id,
            token,
            draft: draft || {
                id
            }
        };
        if (action !== "refresh" && action !== "discover")
            root.registry.subscriptionOwner = root.pending;
        operation.command = [root.helperPath, root.backend, action === "refresh" ? "trigger" : action];
        if (action === "refresh")
            operation.command = operation.command.concat([id]);
        operation.running = true;
        if (body)
            operation.write(JSON.stringify(body) + "\n");
        return {
            ok: true,
            pending: true,
            token
        };
    }

    function save(draft, url, intervalSeconds, replacingId, expectedRevision, expectedProfile) {
        const current = root.registry.profiles.find(profile => profile.id === draft.id) || null;
        if ((replacingId && replacingId !== draft.id) || (current && (replacingId !== draft.id || current.type !== "subscription")) || (!current && replacingId))
            return {
                ok: false,
                field: "id",
                message: "Choose a unique ID; existing subscription IDs cannot change"
            };
        let previous = null;
        if (replacingId) {
            const baseline = ProfileMutation.validateProfile(expectedProfile);
            if (!baseline.ok || JSON.stringify(baseline.profile) !== JSON.stringify(current))
                return {
                    ok: false,
                    field: "storage",
                    message: "Calendar profile changed; reopen it before saving"
                };
            previous = baseline.profile;
        }
        const profile = Object.assign({}, previous || {
            visible: true
        }, draft);
        const valid = ProfileMutation.validateProfile(profile);
        if (!valid.ok)
            return valid;
        if (valid.profile.type !== "subscription")
            return {
                ok: false,
                field: "type",
                message: "Use subscription calendar type"
            };
        return root.start("save", draft.id, {
            profile: valid.profile,
            expectedProfile: previous,
            expectedRevision: expectedRevision === undefined ? root.revision : expectedRevision,
            url,
            intervalSeconds
        }, valid.profile);
    }

    function remove(id) {
        const profile = root.registry.profiles.find(candidate => candidate.id === id);
        if (!profile || profile.type !== "subscription")
            return {
                ok: false,
                field: "id",
                message: "Subscription not found"
            };
        return root.start("remove", id, {
            id,
            expectedProfile: profile,
            expectedRevision: root.revision
        });
    }

    function refresh(id) {
        if (!root.recordForId(id))
            return {
                ok: false,
                field: "id",
                message: "Subscription not found"
            };
        return root.start("refresh", id);
    }

    function ended(exitCode) {
        const request = root.pending;
        if (!request)
            return;
        let reply;
        try {
            reply = JSON.parse(operationOutput.text);
        } catch (error) {
            reply = null;
        }
        if (!reply || typeof reply.ok !== "boolean" || (reply.ok && (exitCode !== 0 || (request.action === "discover" ? !Array.isArray(reply.calendars) : reply.id !== request.id))))
            reply = {
                ok: false,
                field: "storage",
                message: "Subscription helper failed; inspect calendar state before retrying"
            };
        if (root.registry.subscriptionOwner === request)
            root.registry.subscriptionOwner = null;
        root.pending = null;
        if (request.action !== "discover") {
            if ((reply.ok && (request.action === "save" || request.action === "create")) || (reply.converted && request.action.startsWith("attach-"))) {
                // First Add can create directories that did not exist when watching began.
                root.configWatcher.reload();
                root.statusWatcher.reload();
            }
            root.registry.reloadFromDisk();
            root.reload();
        }
        root.finishReply(Object.assign({}, reply, {
            action: request.action,
            id: request.id,
            token: request.token
        }));
    }

    function finishReply(result) {
        root.finished(result);
    }

    Component.onCompleted: root.reload()

    property FileView configWatcher: FileView {
        path: root.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: root.reload()
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.error("Calendar " + root.backend + " configuration: " + FileViewError.toString(error));
        }
    }
    property FileView statusWatcher: FileView {
        path: root.statePath
        printErrors: false
        watchChanges: true
        onFileChanged: root.reload()
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.error("Calendar " + root.backend + " status: " + FileViewError.toString(error));
        }
    }
    property Process listingProcess: Process {
        id: listing
        command: [root.helperPath, root.backend, "list"]
        stdout: StdioCollector {
            id: listOutput
        }
        onExited: (exitCode, exitStatus) => root.listed(exitCode)
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!listing.running && listOutput.text.length === 0)
                        root.listed(-1);
                });
        }
    }
    property Process operationProcess: Process {
        id: operation
        stdinEnabled: true
        stdout: StdioCollector {
            id: operationOutput
        }
        onExited: (exitCode, exitStatus) => root.ended(exitCode)
        onRunningChanged: {
            if (!running && root.pending) {
                const request = root.pending;
                Qt.callLater(() => {
                    if (root.pending === request && !operation.running)
                        root.ended(-1);
                });
            }
        }
    }
}
