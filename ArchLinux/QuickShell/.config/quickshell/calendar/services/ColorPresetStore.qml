import QtQuick
import Quickshell
import Quickshell.Io
import "../common/ColorPresets.js" as ColorPresets

QtObject {
    id: root

    required property var registry
    property var colors: []
    property bool ready: false
    property string errorMessage: ""
    property bool directoryReady: false
    property bool fileMissing: false
    property bool writeFinished: false
    property string writeError: ""
    readonly property string filePath: {
        const stateHome = Quickshell.env("XDG_STATE_HOME");
        if (stateHome)
            return stateHome + "/quickshell-calendar/color-presets.json";
        const home = Quickshell.env("HOME");
        return home ? home + "/.local/state/quickshell-calendar/color-presets.json" : "";
    }
    readonly property string directoryPath: root.filePath.slice(0, root.filePath.lastIndexOf("/"))

    function loadText(text) {
        const result = ColorPresets.parse(text);
        root.fileMissing = false;
        root.ready = result.ok;
        root.errorMessage = result.ok ? "" : result.message;
        if (result.ok)
            root.colors = result.colors;
    }

    function writeColors(candidate) {
        root.writeFinished = false;
        root.writeError = "";
        root.presetFile.setText(JSON.stringify({
            version: 1,
            colors: candidate
        }, null, 2) + "\n");
        if (!root.writeFinished || root.writeError) {
            root.errorMessage = root.writeError || "Color preset write did not complete";
            return false;
        }
        root.colors = candidate;
        root.fileMissing = false;
        root.ready = true;
        root.errorMessage = "";
        return true;
    }

    function seedIfReady() {
        if (root.fileMissing && root.registry.ready)
            root.writeColors(ColorPresets.seed(root.registry.profiles));
    }

    function canAdd(value) {
        const color = ColorPresets.normalizeColor(value);
        return root.ready && color.length > 0 && !root.colors.includes(color);
    }

    function add(value) {
        return root.canAdd(value) && root.writeColors(root.colors.concat([ColorPresets.normalizeColor(value)]));
    }

    function remove(value) {
        const color = ColorPresets.normalizeColor(value);
        if (!root.ready || !color || !root.colors.includes(color))
            return false;
        return root.writeColors(root.colors.filter(existing => existing !== color));
    }

    property Connections registryConnection: Connections {
        target: root.registry
        function onReadyChanged() {
            root.seedIfReady();
        }
    }

    Component.onCompleted: {
        if (root.filePath)
            root.directoryProcess.running = true;
        else
            root.errorMessage = "HOME and XDG_STATE_HOME are not available";
    }

    property Process directoryProcess: Process {
        command: ["install", "-d", "-m", "700", "--", root.directoryPath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.directoryReady = true;
            else
                root.errorMessage = "Could not prepare color preset directory";
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!root.directoryProcess.running && !root.directoryReady && !root.errorMessage)
                        root.errorMessage = "Could not prepare color preset directory";
                });
        }
    }

    property FileView presetFile: FileView {
        path: root.directoryReady ? root.filePath : ""
        preload: true
        atomicWrites: true
        blockWrites: true
        printErrors: false
        watchChanges: true
        onLoaded: {
            if (root.directoryReady)
                root.loadText(text());
        }
        onFileChanged: reload()
        onLoadFailed: error => {
            if (!root.directoryReady)
                return;
            root.ready = false;
            root.fileMissing = error === FileViewError.FileNotFound;
            if (root.fileMissing) {
                root.errorMessage = "";
                root.seedIfReady();
            } else {
                root.errorMessage = "Could not load color presets: " + FileViewError.toString(error);
            }
        }
        onSaved: {
            root.writeFinished = true;
            root.writeError = "";
        }
        onSaveFailed: error => {
            root.writeFinished = true;
            root.writeError = "Could not save color presets: " + FileViewError.toString(error);
        }
    }
}
