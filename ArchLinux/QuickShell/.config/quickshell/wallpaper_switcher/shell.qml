//@ pragma StateDir $BASE/quickshell
// This file does the following:
// 1. creates Theme
// 2. creates AppState
// 3. creates MainWindow
// 4. finds the selected ShellScreen
// 5. creates MonitorContour on that screen
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland

import qs.core as Core
import qs.overlays as Overlays
import qs.services as Services
import qs.ui as Ui

Scope {
    id: root

    // Shared application configuration.
    Core.Theme {
        id: theme
    }

    // Shared mutable application state.
    Core.AppState {
        id: appState
    }

    // Convert the selected Hyprland monitor ID into a ShellScreen
    // that can be assigned to MonitorContour.targetScreen.
    readonly property ShellScreen selected_screen: {
        const monitors = Hyprland.monitors.values;

        if (monitors.length === 0)
            return null;

        for (const screen of Quickshell.screens) {
            const monitor = Hyprland.monitorFor(screen);

            if (monitor && monitor.id === appState.chosen_monitor)
                return screen;
        }

        return null;
    }

    Services.WallpaperService {
        id: wallpaper_service

        appState: appState
    }

    Ui.MainWindow {
        id: main_window

        theme: theme
        appState: appState
        wallpaperService: wallpaper_service
        onFlashRequested: {
            flashing.flash();
        }

        onPreviewRequested: {
            wallpaper_preview.togglePreview();
        }
    }

    Overlays.MonitorContour {
        id: flashing

        theme: theme
        targetScreen: root.selected_screen

        visible: root.selected_screen !== null
    }

    Overlays.WallpaperPreview {
        id: wallpaper_preview

        appState: appState
        theme: theme
        previewScreen: root.selected_screen
    }
}
