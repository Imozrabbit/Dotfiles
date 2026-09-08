import QtQuick
import Quickshell
import Quickshell.Io
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    required property var calendars
    required property var reservedUids
    readonly property string filePath: {
        const home = Quickshell.env("HOME");
        return home ? home + "/.local/share/calendars/personal.json" : "";
    }
    property var rawEvents: []
    property bool ready: false
    property string errorMessage: ""
    property bool writeFinished: false
    property string writeError: ""

    function failure(message) {
        return { ok: false, field: "storage", message };
    }

    function protect(message) {
        root.ready = false;
        root.rawEvents = [];
        root.errorMessage = message;
        console.error("Personal calendar: " + message);
    }

    function loadText(text) {
        const result = EventMutation.parsePersonalStore(
            text, root.calendars, root.reservedUids);
        if (!result.ok) {
            root.protect(result.message);
            return;
        }
        root.rawEvents = result.rawEvents;
        root.errorMessage = "";
        root.ready = true;
    }

    function writeCandidate(candidate) {
        const result = EventMutation.serializePersonalStore(
            candidate, root.calendars, root.reservedUids);
        if (!result.ok)
            return result;

        root.writeFinished = false;
        root.writeError = "";
        personalFile.setText(result.text);
        if (!root.writeFinished)
            return root.failure("Personal calendar write did not complete");
        if (root.writeError.length > 0)
            return root.failure(root.writeError);

        root.rawEvents = result.rawEvents;
        root.errorMessage = "";
        return { ok: true };
    }

    function initializeEmpty() {
        const result = root.writeCandidate([]);
        if (result.ok)
            root.ready = true;
        else
            root.protect(result.message);
    }

    function persist(candidate) {
        if (!root.ready)
            return root.failure(root.errorMessage.length > 0
                ? root.errorMessage : "Personal calendar is not ready");
        return root.writeCandidate(candidate);
    }

    Component.onCompleted: {
        if (root.filePath.length === 0)
            root.protect("HOME is not available");
    }

    property FileView personalFile: FileView {
        path: root.filePath
        preload: true
        atomicWrites: true
        blockWrites: true
        watchChanges: false

        onLoaded: root.loadText(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.initializeEmpty();
            else
                root.protect("Could not load personal.json: "
                    + FileViewError.toString(error));
        }
        onSaved: {
            root.writeFinished = true;
            root.writeError = "";
        }
        onSaveFailed: error => {
            root.writeFinished = true;
            root.writeError = "Could not save personal.json: "
                + FileViewError.toString(error);
        }
    }
}
