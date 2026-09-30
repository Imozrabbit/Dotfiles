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

    function applyResult(result) {
        if (!result.ok || !root.ready)
            return result.ok ? {
                ok: false,
                field: "storage",
                message: "Profile registry is read-only"
            } : result;
        return root.writeProfiles(result.profiles);
    }

    function createProfile(draft) {
        return root.applyResult(ProfileMutation.createProfile(root.profiles, draft));
    }

    function updateProfile(id, changes) {
        return root.applyResult(ProfileMutation.updateProfile(root.profiles, id, changes));
    }

    function removeProfile(id) {
        return root.applyResult(ProfileMutation.removeProfile(root.profiles, id));
    }

    function setVisible(id, visible) {
        return root.applyResult(ProfileMutation.setVisible(root.profiles, id, visible));
    }

    function initializeDefaults() {
        const result = root.writeProfiles(ProfileMutation.defaultProfiles());
        if (result.ok) {
            root.ready = true;
            root.errorMessage = "";
        } else {
            root.protect(result.message);
        }
    }

    Component.onCompleted: {
        if (root.filePath.length === 0)
            root.protect("HOME is not available");
        else
            directoryProcess.running = true;
    }

    property Process directoryProcess: Process {
        id: directoryProcess
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
