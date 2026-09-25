import QtQuick
import Quickshell
import Quickshell.Io
import "../common/EventMutation.js" as EventMutation

QtObject {
    id: root

    property string sourceId: "edt_unistra"
    readonly property string filePath: {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        if (dataHome && dataHome.length > 0)
            return dataHome + "/calendars/" + root.sourceId + ".json";
        const home = Quickshell.env("HOME");
        return home ? home + "/.local/share/calendars/" + root.sourceId + ".json" : "";
    }
    property var rawEvents: []
    property bool ready: false
    property string errorMessage: ""

    function loadText(text) {
        const result = EventMutation.parseImportedStore(text, root.sourceId);
        if (!result.ok) {
            root.errorMessage = result.message;
            console.error("Imported calendar: " + result.message);
            return;
        }
        root.rawEvents = result.rawEvents;
        root.errorMessage = "";
        root.ready = true;
    }

    Component.onCompleted: {
        if (root.filePath.length === 0) {
            root.errorMessage = "HOME is not available";
            console.error("Imported calendar: " + root.errorMessage);
        }
    }

    property FileView importedFile: FileView {
        path: root.filePath
        preload: true
        watchChanges: true

        onLoaded: root.loadText(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.ready = false;
                root.errorMessage = "Imported calendar JSON is not available";
                return;
            }
            root.errorMessage = "Could not load imported calendar: " + FileViewError.toString(error);
            console.error("Imported calendar: " + root.errorMessage);
        }
    }
}
