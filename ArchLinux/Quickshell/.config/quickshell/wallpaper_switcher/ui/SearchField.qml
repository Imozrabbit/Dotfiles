pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.core as Core

Item {
    id: root

    // Check the global flag to see if search field should be turn on or not
    readonly property bool search_active: root.appState.if_searchIsland
    enabled: search_active

    // Require basic properties
    required property Core.Theme theme
    required property Core.AppState appState

    // Indicator if the sidebar is opened, originally in Sidebar.qml
    required property bool sidebar_opened

    // Appearance animation
    opacity: {
        if (!root.search_active)
            return 0;
        if (search_field.activeFocus)
            return 1;
        return 0.82;
    }
    scale: {
        if (!root.search_active)
            return 0.5;
        if (search_field.activeFocus)
            return 1;
        return 0.95;
    }
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
    // Focus the field after it appears
    onSearch_activeChanged: {
        if (root.search_active) {
            Qt.callLater(function () {
                search_field.forceActiveFocus(Qt.ShortcutFocusReason);
                search_field.selectAll();
            });
            return;
        }
        search_field.focus = false;
    }

    //Width limits
    property real maximum_width: 600
    readonly property real minimum_width: root.maximum_width / 3
    readonly property real required_width: Math.ceil(search_text_metrics.advanceWidth) + search_field.leftPadding + search_field.rightPadding + 16
    width: Math.min(maximum_width, Math.max(minimum_width, required_width))

    // Height limits
    implicitHeight: 34

    // Build image filename filters from the search field
    readonly property var grid_filter: searchFilter(search_field.text)
    function searchFilter(searchText) {
        const result = searchText.trim().toLowerCase();
        const extensions = ["png", "jpg", "jpeg", "webp", "bmp"];

        // No search: show every supported image
        if (result === "")
            return extensions.map(extension => "*." + extension);

        // Allow search by extension
        const extension_search = result.startsWith(".") ? result.slice(1) : result;

        if (extensions.includes(extension_search))
            return ["*." + extension_search];

        // Otherwise search inside the filename
        return extensions.map(extension => "*" + result + "*." + extension);
    }

    // Grab the focus when search field appears
    onEnabledChanged: {
        if (enabled) {
            search_field.forceActiveFocus();
            search_field.selectAll();
        }
        if (!enabled) {
            search_field.clear();
        }
    }

    //Focus the search field with ctrl + F or /
    Shortcut {
        sequences: [StandardKey.Find, "/"]
        context: Qt.WindowShortcut
        enabled: !root.sidebar_opened && !search_field.activeFocus
        onActivated: {
            if (!root.enabled) {
                root.appState.if_searchIsland = true;
                return;
            }
            if (!search_field.activeFocus) {
                search_field.forceActiveFocus();
                return;
            }
        }
    }

    //Escape clears the search first, then closes the island
    Shortcut {
        sequences: [StandardKey.Cancel]
        context: Qt.WindowShortcut
        enabled: root.appState.if_searchIsland && !root.sidebar_opened
        onActivated: {
            if (search_field.text.length > 0) {
                search_field.clear();
                root.forceActiveFocus();
                return;
            }
            root.appState.if_searchIsland = false;
        }
    }

    TextMetrics {
        id: search_text_metrics
        text: search_field.text
        font: search_field.font
    }

    Behavior on width {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    TextField {
        id: search_field

        anchors.fill: parent

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
                    return root.theme.hover_floatingTextFieldBorder;
                return root.theme.floatingTextFieldBorder;
            }
            color: {
                if (search_field.activeFocus)
                    return root.theme.active_floatingTextFieldBg;
                if (search_field.hovered)
                    return root.theme.hover_floatingTextFieldBg;
                return root.theme.floatingTextFieldBg;
            }
        }
    }
}
