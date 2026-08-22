import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string fallbackPath: ""
    property var outputs: ({})
    property int version: 0

    function load(raw) {
        let parsed = {};
        try {
            parsed = JSON.parse(String(raw || "").trim() || "{}");
        } catch (error) {
            console.warn("Lockscreen wallpaper state is invalid:", error);
        }
        outputs = parsed.outputs && typeof parsed.outputs === "object" ? parsed.outputs : ({});
        version += 1;
    }

    function outputFor(screenName) {
        const output = outputs[String(screenName || "")];
        return output && typeof output === "object" ? output : null;
    }

    function pathFor(screenName) {
        const output = outputFor(screenName);
        return output && typeof output.wallpaper === "string" && output.wallpaper.length > 0 ? output.wallpaper : fallbackPath;
    }

    function fillModeFor(screenName) {
        const output = outputFor(screenName);
        const mode = output ? String(output.mode || "fit").toLowerCase() : "fit";

        if (mode === "stretch")
            return Image.Stretch;
        if (mode === "fill" || mode === "crop")
            return Image.PreserveAspectCrop;
        if (mode === "center")
            return Image.Pad;
        if (mode === "tile")
            return Image.Tile;
        return Image.PreserveAspectFit;
    }

    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/wallpapers.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onLoadFailed: root.load("")
        onFileChanged: reload()
    }
}
