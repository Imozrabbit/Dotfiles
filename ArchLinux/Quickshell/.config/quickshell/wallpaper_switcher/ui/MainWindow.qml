pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.core as Core
import qs.services as Services

FloatingWindow {
    id: root

    required property Core.Theme theme
    required property Core.AppState appState
    required property Services.WallpaperService wallpaperService

    signal flashRequested
    signal previewRequested

    onClosed: Qt.quit()

    // Main window setup
    title: "wallpaper-switcher"
    color: theme.bg

    implicitWidth: 1000
    implicitHeight: 900

    // Remove focus from the search field when clicking outside it
    TapHandler {
        parent: root.contentItem
        onTapped: event_point => {
            const local_point = search_field.mapFromItem(root.contentItem, event_point.scenePosition);
            if (!search_field.contains(local_point)) {
                root.contentItem.forceActiveFocus(Qt.MouseFocusReason);
            }
        }
    }

    // Monitor and fit-mode selection
    SelectionRow {
        id: first_row

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right

            leftMargin: root.theme.gapLarge
            rightMargin: root.theme.gapLarge
            topMargin: root.theme.gapSmall
        }

        theme: root.theme
        appState: root.appState
        onFlashRequested: {
            root.flashRequested();
        }
    }

    WallpaperGrid {
        id: wallpaper_grid

        anchors {
            top: first_row.bottom
            left: parent.left
            right: parent.right
            bottom: search_field.top

            topMargin: root.theme.gapMedium
            leftMargin: root.theme.gapLarge
            rightMargin: root.theme.gapLarge
            bottomMargin: root.theme.gapMedium
        }

        theme: root.theme
        appState: root.appState

        onEmpty_area_tapped: {
            root.contentItem.forceActiveFocus(Qt.MouseFocusReason);
        }

        grid_filter: search_field.grid_filter
    }

    SearchField {
        id: search_field
        anchors {
            bottom: last_row.top
            bottomMargin: root.theme.gapMedium
            horizontalCenter: parent.horizontalCenter
        }
        maximum_width: parent.width - root.theme.gapLarge * 20
        theme: root.theme
        appState: root.appState
        sidebar_opened: sidebar.opened
    }

    // Source folder path selection and action buttons
    SelectionFolder {
        id: last_row

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom

            leftMargin: root.theme.gapLarge
            rightMargin: root.theme.gapLarge
            bottomMargin: root.theme.gapMedium
        }

        theme: root.theme
        appState: root.appState
        wallpaperService: root.wallpaperService
        onPreviewRequested: {
            root.previewRequested();
        }
    }

    Sidebar {
        id: sidebar
        theme: root.theme
        appState: root.appState
    }
}
