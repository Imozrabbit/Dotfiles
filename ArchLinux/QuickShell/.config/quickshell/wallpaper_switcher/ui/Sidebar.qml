pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel

import qs.core as Core

Drawer {
    id: root

    // Remove focus from the search field when clicking outside it while still in the sidebar area
    TapHandler {
        parent: root.contentItem
        onTapped: event_point => {
            const local_point = search_field.mapFromItem(root.contentItem, event_point.position);
            if (!search_field.contains(local_point)) {
                root.contentItem.forceActiveFocus(Qt.MouseFocusReason);
            }
        }
    }

    required property Core.Theme theme
    required property Core.AppState appState

    property url current_folder: appState.chosen_wallpaper_folder

    edge: Qt.LeftEdge

    width: 250
    height: parent ? parent.height : 800

    modal: false
    interactive: true

    // Reset the browser to the currently selected folder when opened
    onAboutToShow: {
        root.current_folder = root.appState.chosen_wallpaper_folder;
    }

    // Convert a file URL into a readable Linux path : parent dir + current dir
    function local_path(file_url) {
        let path = file_url.toString();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.slice(7));
        const folders = path.split("/").filter(folder => folder !== "");
        return folders.slice(-2).join("/");
    }

    // Build image filename filters from the search field
    function searchFilter(searchText) {
        const result = searchText.trim();
        return result === "" ? ["*"] : ["*" + result + "*"];
    }

    // Focus the search field with ctrl + F or /
    Shortcut {
        sequences: [StandardKey.Find, "/"]
        context: Qt.WindowShortcut
        enabled: root.opened && !search_field.activeFocus
        onActivated: {
            search_field.forceActiveFocus();
            search_field.selectAll();
        }
    }

    // Esc clear the search filed
    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        enabled: root.opened && search_field.text.length > 0
        onActivated: search_field.clear()
    }

    // Tab to toggle sidebar
    Shortcut {
        sequences: ["Tab"]
        context: Qt.WindowShortcut
        enabled: root.opened
        onActivated: root.close()
    }

    // Show only readable directories from the current folder
    FolderListModel {
        id: folder_model

        folder: root.current_folder

        showDirs: true
        showDirsFirst: true
        showFiles: true
        caseSensitive: false
        showHidden: false
        showDotAndDotDot: false
        showOnlyReadable: true

        sortField: FolderListModel.Name
        sortReversed: false
        nameFilters: root.searchFilter(search_field.text)
    }

    // Main sidebar surface
    background: Rectangle {
        color: root.theme.sidebarBg
        radius: root.theme.radiusLarge
        border.width: 1
        border.color: root.theme.sidebarSeparator
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Sidebar title and close button
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            // Title centered across the full header width
            Text {
                anchors.centerIn: parent
                text: "Finder"
                color: root.theme.mainColor
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.normalText_fontSize + 4
                font.bold: true
            }
            // Close button positioned independently in the right corner
            ToolButton {
                id: close_button
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.close()
                // Custom icon color
                contentItem: Text {
                    text: " "
                    color: {
                        if (close_button.down)
                            return root.theme.accentPressed;
                        if (close_button.hovered)
                            return root.theme.accentHover;
                        return root.theme.subTextColor;
                    }
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.normalText_fontSize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: null
            }
        }

        // Current path and parent-folder button
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: path_row.implicitHeight + 11

            // Top separator
            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 1
                color: root.theme.sidebarSeparator
            }

            // URL path row
            RowLayout {
                id: path_row
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 8
                    rightMargin: 8
                }
                spacing: root.theme.gapSmall

                ToolButton {
                    id: back_button
                    enabled: folder_model.parentFolder.toString() !== ""
                    onClicked: {
                        root.current_folder = folder_model.parentFolder;
                    }
                    HoverHandler {
                        id: back_button_hover
                    }
                    contentItem: Text {
                        text: "󰁮 "
                        color: {
                            if (back_button.down)
                                return root.theme.accentPressed;
                            if (back_button_hover.hovered)
                                return root.theme.accentHover;
                            return root.theme.subTextColor;
                        }
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.normalText_fontSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: null
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    text: root.local_path(root.current_folder)
                    color: root.theme.subTextColor

                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.normalText_fontSize
                    font.italic: true

                    elide: Text.ElideLeft
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Bottom separator
            Rectangle {
                anchors {
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                height: 1
                color: root.theme.sidebarSeparator
            }
        }

        // Directory list
        ListView {
            id: folder_list

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10

            clip: true
            model: folder_model

            boundsBehavior: Flickable.StopAtBounds

            TapHandler {
                target: null
                gesturePolicy: TapHandler.DragThreshold
                onTapped: {
                    folder_list.forceActiveFocus(Qt.MouseFocusReason);
                }
            }

            delegate: ItemDelegate {
                id: folder_entry

                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                readonly property bool fileIsPic: !fileIsDir && is_picture(fileUrl)

                width: ListView.view.width
                height: 36

                leftPadding: 12
                rightPadding: 12

                function is_picture(fileUrl) {
                    const path = fileUrl.toString().toLowerCase();
                    return /\.(png|jpe?g|webp|gif|bmp|avif)$/.test(path);
                }

                function trimPath(fileUrl) {
                    const url = fileUrl.toString();
                    if (url.startsWith("file://"))
                        return decodeURIComponent(url.slice(7));
                    return url;
                }

                enabled: fileIsDir || fileIsPic
                hoverEnabled: enabled

                onClicked: {
                    // Pass the signal back to onTapped()
                    // So that clicking on an entry item, search field de-focuses
                    root.contentItem.forceActiveFocus(Qt.MouseFocusReason);
                    if (fileIsDir) {
                        const new_folder = fileUrl.toString();
                        const old_folder = root.appState.chosen_wallpaper_folder.toString();
                        if (new_folder !== old_folder) {
                            // Change current working folder
                            root.appState.chosen_wallpaper_folder = new_folder;
                            root.current_folder = new_folder;
                            // Reset wallpaper info when switching folders
                            root.appState.chosen_wallpaper = "";
                            root.appState.chosen_wallpaper_url = "";
                        } else {
                            root.current_folder = fileUrl;
                        }
                    }
                    if (fileIsPic) {
                        root.appState.chosen_wallpaper = trimPath(fileUrl);
                        // URL used by Image.source to read the resolution
                        root.appState.chosen_wallpaper_url = fileUrl;
                    }
                }

                contentItem: RowLayout {
                    spacing: root.theme.gapMedium

                    Text {
                        leftPadding: root.theme.gapSmall
                        text: {
                            if (folder_entry.fileIsDir) {
                                return " ";
                            }
                            if (folder_entry.fileIsPic) {
                                return " ";
                            }
                            return " ";
                        }
                        color: {
                            if (folder_entry.fileIsDir || folder_entry.fileIsPic) {
                                return root.theme.menuEntryIcon;
                            }
                            return root.theme.inactive_infillColor;
                        }
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.normalText_fontSize
                    }

                    Text {
                        Layout.fillWidth: true

                        text: folder_entry.fileName
                        color: {
                            if (folder_entry.fileIsDir || folder_entry.fileIsPic) {
                                return root.theme.mainColor;
                            }
                            return root.theme.inactive_infillColor;
                        }

                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.normalText_fontSize
                        font.italic: !folder_entry.fileIsDir && !folder_entry.fileIsPic ? true : false

                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                background: Rectangle {
                    color: {
                        if ((folder_entry.fileIsDir || folder_entry.fileIsPic) && folder_entry.down) {
                            return root.theme.pressed_infillColor;
                        }
                        if (folder_entry.hovered)
                            return root.theme.hover_infillColor;
                        return "transparent";
                    }
                }
            }
        }

        // Search entries in the current directory
        TextField {
            id: search_field

            Layout.fillWidth: true
            Layout.preferredHeight: 34

            Layout.leftMargin: 13
            Layout.rightMargin: 13
            Layout.topMargin: 13
            Layout.bottomMargin: 13

            // Focus animation
            opacity: activeFocus ? 1 : 0.9
            scale: activeFocus ? 1 : 0.95
            transformOrigin: Item.Center
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            hoverEnabled: true
            selectByMouse: true

            placeholderText: " "
            placeholderTextColor: root.theme.subTextColor

            color: root.theme.mainColor
            selectionColor: root.theme.selectionColor
            selectedTextColor: root.theme.selectedTextColor

            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.normalText_fontSize

            leftPadding: 10
            rightPadding: 10

            Keys.onEscapePressed: {
                search_field.clear();
                search_field.focus = false;
            }

            background: Rectangle {
                radius: root.theme.radiusMedium
                border.width: 1
                border.color: {
                    if (search_field.activeFocus)
                        return root.theme.hover_textFieldBorder;
                    return root.theme.textFieldBorder;
                }
                color: {
                    if (search_field.activeFocus)
                        return root.theme.active_textFieldBg;
                    if (search_field.hovered)
                        return root.theme.hover_textFieldBg;
                    return root.theme.textFieldBg;
                }
            }
        }
    }
}
