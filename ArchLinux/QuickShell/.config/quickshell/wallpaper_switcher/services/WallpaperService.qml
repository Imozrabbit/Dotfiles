pragma ComponentBehavior: Bound

import Quickshell
import QtQml

import qs.core as Core

Scope {
    id: root

    required property Core.AppState appState

    function refresh() {
        const folder_to_refresh = root.appState.chosen_wallpaper_folder;
        if (folder_to_refresh.toString() === "")
            return;
        root.appState.chosen_wallpaper_folder = "";
        root.reset();
        Qt.callLater(function () {
            root.appState.chosen_wallpaper_folder = folder_to_refresh;
        });
    }

    function reset() {
        root.appState.chosen_wallpaper_url = "";
        root.appState.chosen_wallpaper = "";
    }

    function apply(wallpaperUtility, monitor_name, wallpaper_path, fit_mode) {
        const path = wallpaper_path.toString();
        if (monitor_name === "") {
            console.warn("No monitor selected.");
            return;
        }
        if (path === "") {
            console.warn("No wallpaper selected.");
            return;
        }
        if (fit_mode === "") {
            console.warn("No fit mode selected");
            return;
        }
        const mode = fit_mode.toLowerCase();
        const utility = wallpaperUtility.toLowerCase();

        if (utility !== "swaybg" && utility !== "hyprpaper") {
            console.warn("Unknown wallpaper utility:", utility);
            return;
        }

        wallpaper_state_store.saveSelection(utility, monitor_name, path, mode);
    }

    WallpaperStateStore {
        id: wallpaper_state_store

        onSelectionSaved: path => {
            Quickshell.execDetached([Quickshell.shellPath("scripts/apply.sh"), path]);
        }
    }

    Connections {
        target: Quickshell

        // Suppress every successful reload's popup window
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
        }
    }
}
