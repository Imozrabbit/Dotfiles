import QtQuick
import Quickshell
import Quickshell.Io
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    required property var profile
    property var rawEvents: []
    property bool ready: false
    property bool missing: false
    property string errorMessage: ""
    property bool writeFinished: false
    property string writeError: ""
    property bool initializing: false
    property bool mutationBlocked: false
    onMutationBlockedChanged: {
        if (!root.mutationBlocked && root.missing && root.profile.type === "local")
            root.initializeEmpty();
    }
    property int sourceVersion: 0
    property int readingVersion: 0
    property bool readingSource: false
    readonly property string sourcePath: root.filePath.slice(0, -5) + "/source.ics"

    readonly property string filePath: {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const home = dataHome && dataHome.length > 0 ? dataHome : Quickshell.env("HOME") + "/.local/share";
        return home + "/calendars/" + root.profile.id + (root.profile.type === "synced" ? ".sync.json" : ".json");
    }

    function protect(message) {
        root.ready = false;
        root.rawEvents = [];
        root.errorMessage = message;
        if (message.length > 0)
            console.error("Calendar profile " + root.profile.id + ": " + message);
    }

    function loadText(text) {
        const calendar = [root.storageCalendar()];
        const result = root.profile.type === "local" ? EventMutation.parseLocalStore(text, calendar, root.profile.id) : root.profile.type === "synced" ? EventMutation.parseSyncedStore(text, calendar, root.profile.id) : EventMutation.parseImportedStore(text, root.profile.id);
        if (!result.ok) {
            root.protect(result.message);
            return;
        }
        root.rawEvents = result.rawEvents;
        root.ready = true;
        root.missing = false;
        root.errorMessage = result.warnings && result.warnings.length > 0 ? result.warnings.join("; ") : "";
    }

    function persist(candidate) {
        if (root.mutationBlocked)
            return {
                ok: false,
                field: "storage",
                message: "Calendar conversion is running or settings are not ready"
            };
        if (root.profile.type !== "local")
            return {
                ok: false,
                field: "calendarId",
                message: "Calendar is read-only"
            };
        if (!root.ready)
            return {
                ok: false,
                field: "storage",
                message: root.errorMessage || "Calendar is not ready"
            };
        const result = EventMutation.serializeLocalStore(candidate, [root.storageCalendar()], root.profile.id);
        if (!result.ok)
            return result;
        root.writeFinished = false;
        root.writeError = "";
        profileFile.setText(result.text);
        if (!root.writeFinished)
            return {
                ok: false,
                field: "storage",
                message: "Calendar write did not complete"
            };
        if (root.writeError.length > 0)
            return {
                ok: false,
                field: "storage",
                message: root.writeError
            };
        root.rawEvents = result.rawEvents;
        return {
            ok: true
        };
    }

    function initializeEmpty() {
        if (root.initializing || root.mutationBlocked)
            return;
        root.initializing = true;
        initializer.running = true;
    }

    function initialized(exitCode) {
        if (!root.initializing)
            return;
        if (exitCode === 0) {
            profileFile.reload();
            profileFile.waitForJob();
        } else
            root.protect("Could not initialize private local calendar data");
        root.initializing = false;
    }

    function storageCalendar() {
        return Object.assign({}, root.profile, {
            writable: root.profile.type === "local" || root.profile.type === "synced"
        });
    }

    function sourceUnavailable(message, missing) {
        root.sourceVersion++;
        root.missing = missing;
        root.protect(message);
    }

    function reloadImported() {
        root.sourceUnavailable("", false);
        if (importedReader.running)
            return;
        root.readingVersion = root.sourceVersion;
        root.readingSource = true;
        importedReader.running = true;
        importedReader.write(JSON.stringify({
            id: root.profile.id
        }) + "\n");
    }

    function importedRead(exitCode) {
        root.readingSource = false;
        if (root.readingVersion !== root.sourceVersion) {
            if (root.errorMessage.length === 0)
                root.reloadImported();
            return;
        }
        let result;
        try {
            result = JSON.parse(importedOutput.text);
        } catch (error) {
            result = null;
        }
        if (exitCode !== 0 || !result || result.ok !== true || result.id !== root.profile.id || typeof result.text !== "string") {
            const message = result && typeof result.message === "string" ? result.message : "Could not load calendar file.";
            root.sourceUnavailable(message, message === "Calendar file missing.");
            return;
        }
        root.loadText(result.text);
    }

    property FileView importedSource: FileView {
        path: root.profile.type === "imported" ? root.sourcePath : ""
        preload: true
        watchChanges: true
        onLoaded: root.reloadImported()
        onFileChanged: {
            root.sourceUnavailable("", false);
            reload();
        }
        onLoadFailed: error => {
            if (root.profile.type === "imported")
                root.sourceUnavailable(error === FileViewError.FileNotFound ? "Calendar file missing." : "Calendar file invalid.", error === FileViewError.FileNotFound);
        }
    }

    property Process importedReadProcess: Process {
        id: importedReader
        stdinEnabled: true
        command: [Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper", "subscriptions", "read-imported"]
        stdout: StdioCollector {
            id: importedOutput
        }
        onExited: (exitCode, exitStatus) => root.importedRead(exitCode)
        onRunningChanged: {
            if (!running && root.readingSource) {
                const version = root.readingVersion;
                Qt.callLater(() => {
                    if (!importedReader.running && root.readingSource && root.readingVersion === version)
                        root.importedRead(-1);
                });
            }
        }
    }

    property Process initializeProcess: Process {
        id: initializer
        command: [Quickshell.env("HOME") + "/.config/quickshell/calendar/parse/calendar-sync-helper", "subscriptions", "initialize-local", root.profile.id]
        onExited: (exitCode, exitStatus) => root.initialized(exitCode)
        onRunningChanged: {
            if (!running && root.initializing)
                Qt.callLater(() => {
                    if (!initializer.running && root.initializing)
                        root.initialized(-1);
                });
        }
    }

    property FileView profileFile: FileView {
        path: root.profile.type === "imported" ? "" : root.filePath
        preload: true
        atomicWrites: root.profile.type === "local"
        blockWrites: root.profile.type === "local"
        watchChanges: root.profile.type === "imported" || root.profile.type === "synced" || root.profile.type === "subscription"
        onLoaded: root.loadText(text())
        onFileChanged: reload()
        onLoadFailed: error => {
            if (root.profile.type === "imported")
                return;
            if (error === FileViewError.FileNotFound) {
                root.missing = true;
                root.ready = false;
                root.rawEvents = [];
                root.errorMessage = "Calendar JSON is not available";
                if (root.profile.type === "local")
                    root.initializeEmpty();
                return;
            }
            root.protect("Could not load calendar: " + FileViewError.toString(error));
        }
        onSaved: {
            root.writeFinished = true;
            root.writeError = "";
        }
        onSaveFailed: error => {
            root.writeFinished = true;
            root.writeError = "Could not save calendar: " + FileViewError.toString(error);
        }
    }
}
