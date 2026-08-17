pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core as Core
import qs.services as Services

RowLayout {
    id: root

    // Convert a file URL into a readable Linux path : parent dir + current dir
    function local_path(file_url) {
        if (!file_url)
            return "";
        let path = file_url.toString();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.slice(7));
        const folders = path.split("/").filter(folder => folder !== "");
        return folders.slice(-2).join("/");
    }

    // Convert a file URL into a full readable Linux path
    function full_local_path(file_url) {
        if (!file_url)
            return "";
        let path = file_url.toString();
        if (path.startsWith("file://"))
            path = decodeURIComponent(path.slice(7));
        return path;
    }

    required property Core.Theme theme
    required property Core.AppState appState
    required property Services.WallpaperService wallpaperService

    signal previewRequested

    spacing: root.theme.gapSmall

    // Sliding folder browser
    Sidebar {
        id: folder_sidebar
        theme: root.theme
        appState: root.appState
    }

    Shortcut {
        sequences: ["Tab"]
        context: Qt.WindowShortcut
        enabled: folder_sidebar.closed
        onActivated: folder_sidebar.open()
    }

    Button {
        id: choose_folder_button
        hoverEnabled: true

        implicitWidth: folder_button_text.implicitWidth + 24
        implicitHeight: folder_button_text.implicitHeight + 10

        onClicked: folder_sidebar.opened ? folder_sidebar.close() : folder_sidebar.open()

        contentItem: Text {
            id: folder_button_text

            text: "Explorer"

            color: root.theme.mainColor

            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.normalText_fontSize
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: root.theme.radiusMedium
            border.width: 1
            border.color: choose_folder_button.hovered ? root.theme.hover_borderColor : root.theme.borderColor
            color: {
                if (choose_folder_button.down)
                    return root.theme.pressed_infillColor;
                if (choose_folder_button.hovered)
                    return root.theme.hover_infillColor;
                return root.theme.infillColor;
            }
        }
    }

    Rectangle {
        id: path_container

        clip: true

        // Default
        color: "#066EA8FF"
        border.color: "#186EA8FF"
        radius: root.theme.radiusMedium
        border.width: 1

        property int maximumWidth: 250
        implicitWidth: maximumWidth
        //implicitHeight: selected_folder_path.implicitHeight
        implicitHeight: choose_folder_button.implicitHeight

        HoverHandler {
            id: path_hover
        }

        TextMetrics {
            id: path_text
            text: selected_folder_path.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.normalText_fontSize
        }

        Text {
            id: selected_folder_path
            text: root.local_path(root.appState.chosen_wallpaper_folder) + "/"

            anchors.left: parent.left
            anchors.leftMargin: root.theme.gapSmall
            anchors.verticalCenter: parent.verticalCenter

            color: root.theme.subTextColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.normalText_fontSize
            font.italic: true

            elide: Text.ElideMiddle
            verticalAlignment: Text.AlignVCenter

            Layout.maximumWidth: 500
        }

        ToolTip {
            id: path_tooltip

            visible: path_hover.hovered
            text: root.full_local_path(root.appState.chosen_wallpaper_folder)
            delay: 300

            x: (parent.width - width) / 2
            y: -height - 6

            leftPadding: 10
            rightPadding: 10
            topPadding: 6
            bottomPadding: 6

            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.toolTip_fontSize
            font.bold: true

            contentItem: Text {
                text: path_tooltip.text
                color: root.theme.mainColor
                font: path_tooltip.font
                horizontalAlignment: Text.AlignHCenter
            }

            background: Rectangle {
                color: root.theme.tooltipBg
                border.color: root.theme.tooltipBorder
                border.width: 1
                radius: root.theme.radiusMedium
            }
        }
    }

    Item {
        id: refresh_button_container
        implicitWidth: refresh_button.implicitWidth
        implicitHeight: refresh_button.implicitHeight

        HoverHandler {
            id: refresh_hover
        }

        ToolButton {
            id: refresh_button

            hoverEnabled: true
            anchors.fill: parent

            onClicked: {
                root.wallpaperService.refresh();
            }

            implicitWidth: 30
            implicitHeight: 30

            display: AbstractButton.IconOnly
            icon.source: "../assets/icons/refresh.svg"
            icon.width: 18
            icon.height: 18
            icon.color: {
                if (refresh_button.down)
                    return root.theme.accentPressed;
                if (refresh_button.hovered)
                    return root.theme.accentHover;
                return root.theme.subTextColor;
            }
            background: null
        }

        ToolTip {
            id: refresh_tooltip

            visible: refresh_hover.hovered
            text: "Refresh"
            delay: 300

            x: (parent.width - width) / 2
            y: -height - 6

            leftPadding: 10
            rightPadding: 10
            topPadding: 6
            bottomPadding: 6

            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.toolTip_fontSize
            font.bold: true

            contentItem: Text {
                text: refresh_tooltip.text
                color: root.theme.mainColor
                font: refresh_tooltip.font
                horizontalAlignment: Text.AlignHCenter
            }

            background: Rectangle {
                color: root.theme.tooltipBg
                border.color: root.theme.tooltipBorder
                border.width: 1
                radius: root.theme.radiusMedium
            }
        }
    }

    Item {
        Layout.fillWidth: true

        implicitWidth: image_resolution.implicitWidth
        implicitHeight: image_resolution.implicitHeight

        Text {
            id: image_resolution

            visible: root.appState.chosen_wallpaper_size.width > 0 && root.appState.chosen_wallpaper_size.height > 0
            text: "Resolution: " + root.appState.chosen_wallpaper_size.width + "x" + root.appState.chosen_wallpaper_size.height

            anchors.centerIn: parent

            color: root.theme.subTextColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.normalText_fontSize
            font.italic: true

            elide: Text.ElideMiddle
            verticalAlignment: Text.AlignVCenter

            Layout.maximumWidth: 500
        }
    }

    ActionButtons {
        theme: root.theme
        appState: root.appState
        wallpaperService: root.wallpaperService
        onPreviewRequested: {
            root.previewRequested();
        }
    }
}
