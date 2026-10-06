pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "widgets" as Proton
import "widgets"
import "core" as ProtonCore

PanelWindow { // qmllint disable uncreatable-type
    id: root
    required property var theme
    required property var service
    property bool barRevealed: true
    property int selectedTab: 0
    property string selectedFamily: ""
    property var confirmation: null
    property ProtonCore.Palette colors: ProtonCore.Palette { theme: root.theme }
    readonly property var blockers: service.snapshot?.blockers ?? []
    readonly property bool canManage: !service.busy && service.snapshot !== null && blockers.length === 0
    visible: false
    color: "transparent"
    focusable: true
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "proton-manager"
    onVisibleChanged: {
        if (visible) {
            if (!root.service.busy) root.service.open();
        } else {
            root.confirmation = null;
            root.selectedFamily = "";
            installedTab.expandedVersion = "";
            launcherTab.closeMenu();
        }
    }
    Connections {
        target: root.service
        function onConfirmationChanged() {
            if (root.visible) root.confirmation = root.service.confirmation;
        }
    }
    Shortcut {
        sequence: "Esc"
        enabled: root.visible && !launcherTab.menuOpen
        onActivated: {
            if (root.confirmation !== null) root.confirmation = null;
            else root.visible = false;
        }
    }
    MouseArea { anchors.fill: parent; onClicked: root.visible = false }
    Rectangle {
        id: managerCard
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.barRevealed ? 17 : 10
        anchors.bottomMargin: root.barRevealed ? 40 : 10
        width: Math.min(580, Math.max(0, root.width - anchors.leftMargin - 10))
        height: Math.min(650, popupContent.implicitHeight + popupContent.anchors.topMargin + popupContent.anchors.bottomMargin, Math.max(0, root.height - anchors.bottomMargin - 10))
        clip: true
        color: root.colors.manager
        border.color: root.colors.border
        radius: 8
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        ColumnLayout {
            id: popupContent
            anchors.fill: parent
            anchors.margins: 13
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 8
            Item {
                Layout.fillWidth: true
                Layout.bottomMargin: 3
                implicitHeight: Math.max(headerTitle.implicitHeight, refreshAction.implicitHeight)
                Proton.Label { id: headerTitle; theme: root.theme; colors: root.colors; anchors.centerIn: parent; text: "Proton Manager"; font.pixelSize: 20; font.bold: true }
                Proton.Action {
                    id: refreshAction
                    theme: root.theme; colors: root.colors
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↻"
                    flat: true
                    enabled: !root.service.busy
                    leftPadding: 0
                    rightPadding: 5
                    implicitWidth: contentItem.implicitWidth
                    Accessible.name: "Refresh"
                    font.pixelSize: 20
                    onClicked: root.service.refresh()
                }
            }
            Rectangle {
                visible: root.blockers.length > 0
                Layout.fillWidth: true
                Layout.preferredWidth: tabCard.width
                Layout.minimumWidth: tabCard.width
                Layout.maximumWidth: tabCard.width
                implicitHeight: warning.implicitHeight + 18
                color: root.colors.warningSurface
                radius: tabCard.radius
                border.color: tabCard.border.color
                border.width: tabCard.border.width
                Proton.Label {
                    id: warning
                    theme: root.theme; colors: root.colors
                    anchors.fill: parent
                    anchors.margins: 9
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.blockers.join("\n")
                    color: root.colors.warning
                    font.pixelSize: 13
                }
            }
            Rectangle {
                id: tabCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: Math.max(tabs.implicitHeight + tabContents.implicitHeight + 30 + (root.selectedTab === 0 ? updateActions.implicitHeight + 22 : 0), root.confirmation !== null ? confirmationOverlay.implicitHeight : 0)
                color: root.colors.tab
                border.color: root.colors.border
                radius: 8
                TabBar {
                    id: tabs
                    enabled: root.confirmation === null
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    currentIndex: root.selectedTab
                    onCurrentIndexChanged: root.selectedTab = currentIndex
                    background: Rectangle { color: "transparent" }
                    Repeater {
                        model: ["Updates", "Installed", "Launcher"]
                        TabButton {
                            id: tab
                            required property string modelData
                            implicitHeight: 36
                            text: modelData
                            HoverHandler { cursorShape: tab.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            contentItem: Text {
                                text: tab.text
                                color: tab.down ? root.colors.foreground : tab.checked ? root.colors.accent : root.colors.secondary
                                font.family: root.theme.fontFamily
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: tab.down ? root.colors.tabPressed : tab.hovered ? root.colors.tabHover : "transparent"
                                radius: 6
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: tab.checked ? 2 : 1; color: tab.checked ? root.colors.tabUnderline : root.colors.guide }
                            }
                        }
                    }
                }
                RowLayout {
                    id: updateActions
                    enabled: root.confirmation === null
                    visible: root.selectedTab === 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    anchors.bottomMargin: 16
                    Proton.Action {
                        theme: root.theme; colors: root.colors
                        text: "Update & clean"
                        enabled: root.canManage && !!root.service.snapshot?.releases[root.selectedFamily]
                        onClicked: root.service.prepareInstall(root.selectedFamily)
                    }
                    Item { Layout.fillWidth: true }
                    Proton.Action { theme: root.theme; colors: root.colors; text: "Clear selection"; enabled: root.selectedFamily !== "" && !root.service.busy; onClicked: root.selectedFamily = "" }
                }
                ScrollView {
                    id: scroll
                    enabled: root.confirmation === null
                    anchors.top: tabs.bottom
                    anchors.bottom: updateActions.visible ? updateActions.top : parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    anchors.bottomMargin: updateActions.visible ? 16 : 10
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        id: tabContents
                        width: scroll.availableWidth
                        spacing: 10
                        UpdatesTab { id: updatesTab; theme: root.theme; colors: root.colors; service: root.service; Layout.fillWidth: true; visible: root.selectedTab === 0; selectedFamily: root.selectedFamily; onFamilySelected: family => root.selectedFamily = family }
                        InstalledTab { id: installedTab; theme: root.theme; colors: root.colors; service: root.service; Layout.fillWidth: true; visible: root.selectedTab === 1 }
                        LauncherTab { id: launcherTab; theme: root.theme; colors: root.colors; service: root.service; Layout.fillWidth: true; visible: root.selectedTab === 2 }
                    }
                }
                Confirmation {
                    id: confirmationOverlay
                    theme: root.theme; colors: root.colors
                    anchors.fill: parent
                    descriptor: root.confirmation
                    busy: root.service.busy
                    onCancelRequested: root.confirmation = null
                    onConfirmRequested: {
                        const descriptor = root.confirmation;
                        root.confirmation = null;
                        root.service.confirm(descriptor);
                    }
                }
            }
            // Shared footer stays outside the scroll area and tab content.
            RowLayout {
                Layout.topMargin: 1
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Proton.Label { theme: root.theme; colors: root.colors; text: root.service.busy ? root.service.progress?.stage ?? "Checking state" : "Ready"; font.pixelSize: 13 }
                Proton.Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: root.service.busy && root.service.progress?.fraction !== null && root.service.progress ? Math.round(root.service.progress.fraction * 100) + "%" : ""; color: root.colors.accent }
            }
            ProgressBar {
                id: progress
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                implicitHeight: 4
                value: root.service.busy ? root.service.progress?.fraction ?? 0 : 0
                background: Rectangle { color: root.colors.progressTrack; radius: 2 }
                contentItem: Item {
                    Rectangle { width: progress.visualPosition * parent.width; height: parent.height; radius: 2; color: root.colors.accent }
                }
            }
            Proton.Label {
                theme: root.theme; colors: root.colors
                Layout.bottomMargin: 1
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                font.pixelSize: 12
                color: root.colors.secondary
                visible: root.service.busy && (root.service.progress?.downloadedBytes ?? 0) > 0
                text: Math.round((root.service.progress?.downloadedBytes ?? 0) / 1048576) + (root.service.progress?.totalBytes ? " / " + Math.round(root.service.progress.totalBytes / 1048576) : "") + " MiB"
            }
        }
    }
}
