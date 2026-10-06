pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

import qs.core as Core
import "../core/BarConfig.js" as BarConfig

Rectangle {
    id: root

    required property Core.Theme theme
    required property var outputScreen

    required property int updateCount
    required property bool checking
    required property bool showTray
    required property bool showWorkspaces
    required property bool showLauncher
    required property bool showUpdates
    required property bool showProtonManager
    required property bool protonManagerOpen
    required property var workspaceDisplay
    required property var launchers

    signal updateRequested
    signal protonManagerRequested

    implicitWidth: workspaceLayout.implicitWidth + 33
    implicitHeight: workspaceLayout.implicitHeight + 4
    color: theme.workspaceBg
    radius: root.theme.radiusMedium

    readonly property var normalEntries: BarConfig.normalWorkspaceEntries(root.workspaceDisplay, Hyprland.workspaces.values)
    readonly property var specialEntries: BarConfig.specialWorkspaceEntries(root.workspaceDisplay, Hyprland.workspaces.values, Hyprland.monitors.values, Hyprland.focusedMonitor)

    onShowTrayChanged: {
        if (!root.showTray && trayDrawer)
            trayDrawer.trayOpened = false;
    }

    RowLayout {
        id: workspaceLayout
        spacing: root.workspaceDisplay.itemSpacing
        anchors.centerIn: parent

        SystemTrayDrawer {
            id: trayDrawer
            visible: root.showTray
            outputScreen: root.outputScreen
            theme: root.theme
        }

        Text {
            id: protonIcon
            visible: root.showProtonManager
            property bool tooltipVisible: false
            text: "󰹂"
            color: protonMouse.containsMouse ? root.theme.launcherHoverColor : root.protonManagerOpen ? root.theme.launcherColor : root.theme.workspaceEmptyColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.launcherFontSize
            font.bold: true
            onVisibleChanged: {
                if (!visible) {
                    protonTooltipDelay.stop();
                    tooltipVisible = false;
                }
            }
            MouseArea {
                id: protonMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: protonTooltipDelay.restart()
                onExited: {
                    protonTooltipDelay.stop();
                    protonIcon.tooltipVisible = false;
                }
                onClicked: {
                    protonTooltipDelay.stop();
                    protonIcon.tooltipVisible = false;
                    root.protonManagerRequested();
                }
            }
            Timer {
                id: protonTooltipDelay
                interval: 300
                onTriggered: protonIcon.tooltipVisible = protonMouse.containsMouse && protonIcon.visible
            }
            SystemStatTooltip {
                visible: protonIcon.tooltipVisible
                anchorItem: protonIcon
                heading: "Proton Manager"
                rows: []
                theme: root.theme
            }
        }

        Rectangle {
            visible: (root.showTray || root.showProtonManager) && root.showWorkspaces
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.theme.workspaceFontSize
            Layout.alignment: Qt.AlignVCenter
            color: root.theme.workspaceEmptyColor
            opacity: 0.7
        }

        Repeater {
            model: root.showWorkspaces ? root.normalEntries : []
            Text {
                id: workspaceText

                required property var modelData

                property var ws: Hyprland.workspaces.values.find(w => w.id === modelData.id)
                property bool isActive: Hyprland.focusedWorkspace?.id === modelData.id
                property bool isOccupied: (ws?.toplevels.values.length ?? 0) > 0

                text: modelData.label
                textFormat: Text.PlainText
                color: workspaceMouse.containsMouse ? root.theme.workspaceHoveredColor : (isActive ? root.theme.workspaceActiveColor : (isOccupied ? root.theme.workspaceOccupiedColor : root.theme.workspaceEmptyColor))
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.workspaceFontSize
                    bold: true
                }
                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + workspaceText.modelData.id + " })")
                }
            }
        }

        Repeater {
            model: root.showWorkspaces ? root.specialEntries : []

            Text {
                id: specialWorkspaceText

                required property var modelData

                text: modelData.label
                textFormat: Text.PlainText
                color: specialWorkspaceMouse.containsMouse ? root.theme.workspaceHoveredColor : modelData.state === "focused" ? root.theme.workspaceActiveColor : modelData.state === "occupied" ? root.theme.specialWorkspaceColor : root.theme.workspaceEmptyColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.workspaceFontSize
                    bold: true
                }
                MouseArea {
                    id: specialWorkspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + JSON.stringify(specialWorkspaceText.modelData.name) + ")")
                }
            }
        }

        Rectangle {
            visible: (root.showTray || root.showProtonManager || root.showWorkspaces) && (root.showLauncher || root.showUpdates)
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.theme.workspaceFontSize
            Layout.alignment: Qt.AlignVCenter
            color: root.theme.workspaceEmptyColor
            opacity: 0.7
        }

        LauncherDrawer {
            launchers: root.launchers
            visible: root.showLauncher || root.showUpdates
            updateCount: root.updateCount
            checking: root.checking
            onUpdateRequested: root.updateRequested()
            showLauncher: root.showLauncher
            showUpdates: root.showUpdates
            itemSpacing: root.workspaceDisplay.itemSpacing
            theme: root.theme
        }
    }
}
