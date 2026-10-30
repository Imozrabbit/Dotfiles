import QtQuick
import Quickshell
import Quickshell.Io
import "../common/ProfileMutation.js" as ProfileMutation

QtObject {
    id: root

    property var profiles: ProfileMutation.defaultProfiles()
    property bool ready: false
    property string errorMessage: ""
    property bool writeFinished: false
    property string writeError: ""
    property bool directoryReady: false
    property var importOwner: null
    property var subscriptionOwner: null
    property var localRemovalPending: null
    property var localRemovalResult: null
    property int removalSerial: 0
    property bool initializing: false
    readonly property string filePath: {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        if (dataHome && dataHome.length > 0)
            return dataHome + "/calendars/profiles.json";
        const home = Quickshell.env("HOME");
        return home ? home + "/.local/share/calendars/profiles.json" : "";
    }
    readonly property string directoryPath: root.filePath.length > 0 ? root.filePath.slice(0, root.filePath.lastIndexOf("/")) : ""

    function protect(message) {
        root.ready = false;
        root.errorMessage = message;
        console.error("Calendar profiles: " + message);
    }

    function loadText(text) {
        const result = ProfileMutation.parseRegistry(text);
        if (!result.ok) {
            root.protect(result.message);
            return;
        }
        root.profiles = result.profiles;
        root.ready = true;
        root.errorMessage = "";
    }

    function writeProfiles(candidate) {
        const result = ProfileMutation.serializeRegistry(candidate);
        if (!result.ok)
            return result;
        root.writeFinished = false;
        root.writeError = "";
        registryFile.setText(result.text);
        if (!root.writeFinished)
            return {
                ok: false,
                field: "storage",
                message: "Profile registry write did not complete"
            };
        if (root.writeError.length > 0)
            return {
                ok: false,
                field: "storage",
                message: root.writeError
            };
        root.profiles = result.profiles;
        return {
            ok: true,
            profiles: result.profiles
        };
    }

    function applyResult(result, owner) {
        if (!result.ok || !root.ready)
            return result.ok ? {
                ok: false,
                field: "storage",
                message: "Profile registry is read-only"
            } : result;
        if (root.subscriptionOwner || root.localRemovalPending || root.importOwner)
            return {
                ok: false,
                field: "storage",
                message: "Calendar settings are changing; wait before changing calendar profiles"
            };
        if (JSON.stringify(result.profiles) === JSON.stringify(root.profiles))
            return {
                ok: true,
                profiles: root.profiles
            };
        return root.writeProfiles(result.profiles);
    }

    function createProfile(draft, owner) {
        return root.applyResult(ProfileMutation.createProfile(root.profiles, draft), owner);
    }

    function updateProfile(id, changes, owner) {
        return root.applyResult(ProfileMutation.updateProfile(root.profiles, id, changes), owner);
    }

    function removeProfile(id, owner) {
        return root.applyResult(ProfileMutation.removeProfile(root.profiles, id), owner);
    }

    function removeLocalProfile(id, helperPath) {
        if (!root.ready || root.importOwner || root.subscriptionOwner || root.localRemovalPending)
            return {
                ok: false,
                field: "storage",
                message: "Calendar settings are not ready or another change is running"
            };
        const profile = root.profiles.find(candidate => candidate.id === id);
        if (!profile || (profile.type !== "local" && profile.type !== "imported"))
            return {
                ok: false,
                field: "id",
                message: "Local calendar not found"
            };
        const token = ++root.removalSerial;
        root.localRemovalResult = null;
        root.localRemovalPending = {
            id,
            token
        };
        localRemoveOperation.command = [helperPath, "subscriptions", profile.type === "imported" ? "remove-imported" : "remove-local"];
        localRemoveOperation.running = true;
        localRemoveOperation.write(JSON.stringify({
            id,
            expectedProfile: profile
        }) + "\n");
        return {
            ok: true,
            pending: true,
            token
        };
    }

    function finishLocalRemoval(exitCode) {
        const request = root.localRemovalPending;
        if (!request)
            return;
        let reply;
        try {
            reply = JSON.parse(localRemoveOutput.text);
        } catch (error) {
            reply = null;
        }
        if (!reply || typeof reply.ok !== "boolean" || (reply.ok && (exitCode !== 0 || reply.id !== request.id || reply.removed !== true)))
            reply = {
                ok: false,
                field: "storage",
                message: "Local removal helper failed; inspect calendar state before retrying"
            };
        root.localRemovalPending = null;
        root.reloadFromDisk();
        root.localRemovalResult = Object.assign({}, reply, {
            id: request.id,
            token: request.token
        });
    }

    function setVisible(id, visible) {
        return root.applyResult(ProfileMutation.setVisible(root.profiles, id, visible));
    }

    function initializeDefaults() {
        if (root.initializing)
            return;
        root.initializing = true;
        initializer.running = true;
    }

    function initialized(exitCode) {
        if (!root.initializing)
            return;
        root.initializing = false;
        if (exitCode === 0)
            root.reloadFromDisk();
        else
            root.protect("Could not initialize private profile registry");
    }

    function reloadFromDisk() {
        registryFile.reload();
        registryFile.waitForJob();
    }

    Component.onCompleted: {
        if (root.filePath.length === 0)
            root.protect("HOME is not available");
        else
            directoryProcess.running = true;
    }

    property Process directoryProcess: Process {
        command: ["install", "-d", "-m", "700", "--", root.directoryPath]
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.protect("Could not prepare calendar data directory");
                return;
            }
            root.directoryReady = true;
        }
        // qmllint enable signal-handler-parameters
    }

    property Process initializeProcess: Process {
        id: initializer
        command: [Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper", "subscriptions", "initialize-registry"]
        onExited: (exitCode, exitStatus) => root.initialized(exitCode)
        onRunningChanged: {
            if (!running && root.initializing)
                Qt.callLater(() => {
                    if (!initializer.running && root.initializing)
                        root.initialized(-1);
                });
        }
    }

    property Process localRemovalProcess: Process {
        id: localRemoveOperation
        stdinEnabled: true
        stdout: StdioCollector {
            id: localRemoveOutput
        }
        onExited: (exitCode, exitStatus) => root.finishLocalRemoval(exitCode)
        onRunningChanged: {
            if (!running && root.localRemovalPending) {
                const request = root.localRemovalPending;
                Qt.callLater(() => {
                    if (root.localRemovalPending === request && !localRemoveOperation.running)
                        root.finishLocalRemoval(-1);
                });
            }
        }
    }

    property FileView registryFile: FileView {
        path: root.directoryReady ? root.filePath : ""
        preload: true
        atomicWrites: true
        blockWrites: true
        watchChanges: true
        onLoaded: {
            if (root.directoryReady)
                root.loadText(text());
        }
        onFileChanged: reload()
        onLoadFailed: error => {
            if (!root.directoryReady)
                return;
            if (error === FileViewError.FileNotFound) {
                root.initializeDefaults();
                return;
            }
            root.protect("Could not load profile registry: " + FileViewError.toString(error));
        }
        onSaved: {
            root.writeFinished = true;
            root.writeError = "";
        }
        onSaveFailed: error => {
            root.writeFinished = true;
            root.writeError = "Could not save profile registry: " + FileViewError.toString(error);
        }
    }
}
