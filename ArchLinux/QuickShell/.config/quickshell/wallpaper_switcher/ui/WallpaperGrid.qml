pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel

import qs.core as Core
import qs.animations as Animations

Item {
    id: root

    required property Core.Theme theme
    required property Core.AppState appState

    // From SearchField.qml for filtering while searching
    required property var grid_filter

    // Signal indicating clicking on an empty area, for search field to defocus
    signal empty_area_tapped

    FolderListModel {
        id: wallpaper_model

        folder: root.appState.chosen_wallpaper_folder

        nameFilters: root.grid_filter

        // Only expose image files, not directories.
        showDirs: false
        showFiles: true
        showHidden: false
        showOnlyReadable: true
        caseSensitive: false // Match JPG as well as jpg.

        sortField: FolderListModel.Name
    }

    Image {
        id: selected_resolution_reader
        source: root.appState.chosen_wallpaper_url
        visible: false
        asynchronous: true
        cache: false
        onSourceChanged: {
            root.appState.chosen_wallpaper_size = Qt.size(0, 0);
        }
        onStatusChanged: {
            if (status === Image.Ready) {
                root.appState.chosen_wallpaper_size = Qt.size(implicitWidth, implicitHeight);
                return;
            }
            if (status === Image.Error || status === Image.Null)
                root.appState.chosen_wallpaper_size = Qt.size(0, 0);
        }
    }

    GridView {
        id: wallpaper_grid

        anchors.fill: parent
        clip: true

        model: wallpaper_model

        // Animate cards appearing in a newly populated model
        populate: Animations.GridAppear {}

        // Animate individual cards being added
        add: Animations.GridAppear {}

        // Animate cards being removed by filtering
        remove: Animations.GridRemove {}

        // Reposition remaining cards smoothly
        displaced: Animations.GridDisplaced {}

        cellWidth: {
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/3440x1440")
                return 320;
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/1080x1920")
                return 180;
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/515x1920")
                return 145;
            return 320;
        }

        cellHeight: {
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/3440x1440")
                return 180;
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/1080x1920")
                return 360;
            if (root.appState.chosen_wallpaper_folder.toString() === "file:///home/Zrabbit/Pictures/Wallpaper/hyprpaper/515x1920")
                return 360;
            return 180;
        }

        // Detect clicks on empty grid space, excluding wallpaper cards
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: event_point => {
                // indexAt() requires coordinates relative to contentItem
                const content_point = wallpaper_grid.mapToItem(wallpaper_grid.contentItem, event_point.position);
                const clicked_index = wallpaper_grid.indexAt(content_point.x, content_point.y);
                if (clicked_index === -1)
                    root.empty_area_tapped();
            }
        }

        delegate: Item {
            id: wallpaper_delegate

            required property url fileUrl
            required property string fileName
            required property string filePath

            width: wallpaper_grid.cellWidth
            height: wallpaper_grid.cellHeight

            Rectangle {
                id: card

                readonly property bool selected: wallpaper_delegate.filePath === root.appState.chosen_wallpaper

                anchors.fill: parent
                anchors.margins: 6

                color: card_hover.hovered ? root.theme.hover_gridcardColor : root.theme.gridcardColor
                radius: root.theme.radiusLarge

                border.width: selected ? 2 : 1
                border.color: {
                    if (selected)
                        return root.theme.selected_gridborderColor;
                    if (card_hover.hovered)
                        return root.theme.hover_gridborderColor;

                    return root.theme.gridborderColor;
                }

                Image {
                    id: preview

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        bottom: wallpaper_name.top

                        topMargin: 8
                        leftMargin: 8
                        rightMargin: 8
                    }

                    source: wallpaper_delegate.fileUrl
                    fillMode: Image.PreserveAspectFit

                    asynchronous: true
                    cache: false

                    // Decode a thumbnail-sized image rather than retaining
                    // the wallpaper's full resolution in memory.
                    sourceSize: Qt.size(320, 180)
                }

                Text {
                    id: wallpaper_name

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom

                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 8
                    }

                    text: wallpaper_delegate.fileName
                    color: card.selected ? root.theme.mainColor : root.theme.subTextColor

                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.normalText_fontSize

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                HoverHandler {
                    id: card_hover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: {
                        // Normal Linux path used by the wallpaper service
                        root.appState.chosen_wallpaper = wallpaper_delegate.filePath;
                        // URL used by Image.source to read the resolution
                        root.appState.chosen_wallpaper_url = wallpaper_delegate.fileUrl;
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent

        visible: wallpaper_model.status === FolderListModel.Ready && wallpaper_model.count === 0

        text: "No wallpapers found"
        color: root.theme.mainColor

        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.normalText_fontSize
    }
}
