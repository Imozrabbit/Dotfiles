import QtQuick
import Quickshell.Io
import "../common/ProfileMutation.js" as ProfileMutation

QtObject {
    id: root

    required property var registry
    required property string helperPath
    property var pending: null
    readonly property bool busy: root.pending !== null
    signal finished(var result)

    function begin(draft, source, replacingId, sourceKind) {
        if (root.busy || root.registry.importOwner || root.registry.subscriptionOwner || root.registry.localRemovalPending)
            return {
                ok: false,
                field: "storage",
                message: "Another calendar change is running"
            };
        if (!root.registry.ready)
            return {
                ok: false,
                field: "storage",
                message: "Profile registry is not ready"
            };
        if (replacingId || (sourceKind && sourceKind !== "file"))
            return {
                ok: false,
                field: "source",
                message: "Add one local ICS file as a new calendar"
            };
        if (typeof source !== "string" || source.length === 0)
            return {
                ok: false,
                field: "source",
                message: "Choose an ICS file"
            };
        const validation = ProfileMutation.createProfile(root.registry.profiles, Object.assign({
            visible: true
        }, draft));
        if (!validation.ok)
            return validation;
        if (validation.profile.type !== "imported")
            return {
                ok: false,
                field: "type",
                message: "Choose an imported calendar"
            };
        root.pending = {
            draft: validation.profile
        };
        root.registry.importOwner = root.pending;
        operation.command = [root.helperPath, "subscriptions", "import-local"];
        operation.running = true;
        operation.write(JSON.stringify({
            profile: validation.profile,
            source
        }) + "\n");
        return {
            ok: true,
            pending: true
        };
    }

    function complete(exitCode) {
        const pending = root.pending;
        if (!pending)
            return;
        let result;
        try {
            result = JSON.parse(output.text);
        } catch (error) {
            result = null;
        }
        if (!result || typeof result.ok !== "boolean" || (result.ok && (exitCode !== 0 || result.id !== pending.draft.id)) || (!result.ok && (typeof result.message !== "string" || result.message.length === 0)))
            result = {
                ok: false,
                field: "storage",
                message: "Import interrupted; check calendar list before retrying."
            };
        root.registry.reloadFromDisk();
        if (root.registry.importOwner === pending)
            root.registry.importOwner = null;
        root.pending = null;
        root.finished(result);
    }

    property Process importProcess: Process {
        id: operation
        stdinEnabled: true
        stdout: StdioCollector {
            id: output
        }
        onExited: (exitCode, exitStatus) => root.complete(exitCode)
        onRunningChanged: {
            if (!running && root.pending) {
                const request = root.pending;
                Qt.callLater(() => {
                    if (!operation.running && root.pending === request)
                        root.complete(-1);
                });
            }
        }
    }
}
