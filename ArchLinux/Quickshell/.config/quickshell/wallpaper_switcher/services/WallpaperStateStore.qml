pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQml

Scope {
    id: root

    property alias utility: wallpaper_state.utility
    property alias outputs: wallpaper_state.outputs
    property bool selection_save_pending: false
    signal selectionSaved(string path)

    function saveSelection(utility, monitor_name, wallpaper_path, fit_mode) {
        const saved_outputs = root.utility === utility ? Object.assign({}, root.outputs || {}) : {};

        saved_outputs[monitor_name] = {
            wallpaper: wallpaper_path,
            mode: fit_mode.toLowerCase()
        };

        root.utility = utility;
        root.outputs = saved_outputs;

        root.selection_save_pending = true;
        wallpaper_state_file.writeAdapter();
    }

    FileView {
        id: wallpaper_state_file

        path: Quickshell.statePath("wallpapers.json")
        printErrors: false

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                wallpaper_state_file.writeAdapter();
                return;
            }
            console.error("Failed to load wallpaper state:", FileViewError.toString(error));
        }

        onSaveFailed: error => {
            root.selection_save_pending = false;
            console.error("Failed to save wallpaper state:", FileViewError.toString(error));
        }

        onSaved: {
            console.log("Wallpaper state saved:", wallpaper_state_file.path);
            if (root.selection_save_pending) {
                root.selection_save_pending = false;
                root.selectionSaved(wallpaper_state_file.path);
            }
        }

        JsonAdapter { // qmllint disable unresolved-type
            id: wallpaper_state
            property int version: 1
            property string utility: ""
            property var outputs: ({})
        }
    }
}
