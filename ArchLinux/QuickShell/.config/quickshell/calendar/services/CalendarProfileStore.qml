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

    readonly property string filePath: {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const home = dataHome && dataHome.length > 0 ? dataHome : Quickshell.env("HOME") + "/.local/share";
        return home + "/calendars/" + root.profile.id + (root.profile.type === "synced" ? ".sync.json" : ".json");
    }

    function protect(message) {
        root.ready = false;
        root.rawEvents = [];
        root.errorMessage = message;
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
        const result = EventMutation.serializeLocalStore([], [root.storageCalendar()], root.profile.id);
        if (!result.ok) {
            root.protect(result.message);
            return;
        }
        root.writeFinished = false;
        root.writeError = "";
        profileFile.setText(result.text);
        if (root.writeFinished && root.writeError.length === 0) {
            root.ready = true;
            root.missing = false;
            root.errorMessage = "";
        } else {
            root.protect(root.writeError || "Calendar file initialization did not complete");
        }
    }

    function storageCalendar() {
        return Object.assign({}, root.profile, {
            writable: root.profile.type === "local" || root.profile.type === "synced"
        });
    }

    property FileView profileFile: FileView {
        path: root.filePath
        preload: true
        atomicWrites: root.profile.type === "local"
        blockWrites: root.profile.type === "local"
        watchChanges: root.profile.type === "imported" || root.profile.type === "synced"
        onLoaded: root.loadText(text())
        onFileChanged: reload()
        onLoadFailed: error => {
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
