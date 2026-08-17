// This file stores values that can change while the application runs
import QtQuick

QtObject {
    // Set up the default selection
    property int chosen_monitor: -1
    property string chosen_monitor_name: ""
    property string chosen_mode: ""

    // Set up the default wallpaper folder
    property url chosen_wallpaper_folder: "file:///home/Zrabbit/Pictures/Wallpaper/1920x1080"

    // Set up the selected wallpaper file unix path, its url(for resolution reading) and its size
    property string chosen_wallpaper: ""
    property url chosen_wallpaper_url: ""
    property size chosen_wallpaper_size: Qt.size(0, 0)

    // Set up the underlying wallpaper utility
    property string chosen_utility: utilities.length > 0 ? utilities[0] : ""

    // Check if the search fiels is active or not
    property bool if_searchIsland: false

    // Check if the preview window is on
    property bool if_preview: false

    // The list of available modes
    readonly property var modes: {
        if (chosen_utility === "swaybg")
            return ["stretch", "fill", "fit", "center", "tile"];
        if (chosen_utility === "hyprpaper")
            return ["Cover", "Tile", "Fill", "Contain"];
        [];
    }

    // The list of available wallpaper utilities
    readonly property var utilities: ["swaybg", "hyprpaper"]

    // Set up the fit mode of the Qt's own preview machine
    readonly property int imageFillMode: {
        const mode = chosen_mode.toLowerCase();
        switch (mode) {
        case "fill":
        case "cover":
            return Image.PreserveAspectCrop;
        case "fit":
        case "contain":
            return Image.PreserveAspectFit;
        case "stretch":
            return Image.Stretch;
        case "center":
            return Image.Pad;
        case "tile":
            return Image.Tile;
        default:
            return Image.PreserveAspectCrop;
        }
    }
}
