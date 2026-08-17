pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

import qs.core as Core

Rectangle {
    id: root

    required property Core.Theme theme

    required property int updateCount
    required property bool checking

    signal updateRequested

    implicitWidth: workspaceLayout.implicitWidth + 33
    implicitHeight: workspaceLayout.implicitHeight + 4
    color: theme.workspaceBg
    radius: root.theme.radiusMedium

    property var workspaces: ["1", "2", "3", "󰝆", "󰐫", "", ""]
    property var special_workspaces: [
        {
            name: "rmpc",
            icon: ""
        },
        {
            name: "steam",
            icon: ""
        }
    ]

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activespecial")
                Hyprland.refreshMonitors();
        }
    }

    RowLayout {
        id: workspaceLayout
        spacing: 21
        anchors.centerIn: parent

        // This is for creating normal workspaces
        Repeater {
            model: root.workspaces
            Text {
                id: workspaceText

                required property int index
                required property string modelData

                property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
                property int ws_num: index + 1

                text: modelData
                color: workspaceMouse.containsMouse ? root.theme.workspaceHoveredColor : (isActive ? root.theme.workspaceActiveColor : (ws ? root.theme.workspaceOccupiedColor : root.theme.workspaceEmptyColor))
                font {
                    pixelSize: root.theme.workspaceFontSize
                    bold: true
                }
                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + (workspaceText.index + 1) + " })")
                }
            }
        }

        // This is for creating special workspaces
        Repeater {
            model: root.special_workspaces.filter(entry => Hyprland.workspaces.values.some(workspace => workspace.name === "special:" + entry.name))

            Text {
                id: specialWorkspaceText

                required property var modelData

                property var ws: Hyprland.workspaces.values.find(workspace => workspace.name === "special:" + modelData.name)
                property bool occupied: ws ? ws.toplevels.values.length > 0 : false
                property bool opened: Hyprland.monitors.values.some(monitor => monitor.lastIpcObject?.specialWorkspace?.name === "special:" + modelData.name)

                text: modelData.icon
                color: specialWorkspaceMouse.containsMouse ? root.theme.workspaceHoveredColor : (opened && occupied ? root.theme.specialWorkspaceColor : root.theme.workspaceEmptyColor)
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
                    onClicked: Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + specialWorkspaceText.modelData.name + '")')
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.theme.workspaceFontSize
            Layout.alignment: Qt.AlignVCenter
            color: root.theme.workspaceEmptyColor
            opacity: 0.7
        }

        LauncherDrawer {
            updateCount: root.updateCount
            checking: root.checking
            onUpdateRequested: root.updateRequested()
            theme: root.theme
        }
    }
}
