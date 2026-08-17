pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core as Core

RowLayout {
    id: root

    required property Core.Theme theme

    required property int updateCount
    required property bool checking

    signal updateRequested

    property int drawerGap: 10

    readonly property bool expanded: drawerHover.hovered
    HoverHandler {
        id: drawerHover
    }

    property var launchers: [
        {
            icon: "󰸉 ",
            tooltip: "Wallpaper Switcher",
            leftCommand: ["quickshell", "-c", "wallpaper_switcher"],
            rightCommand: []
        },
        {
            icon: "󰔎 ",
            tooltip: "Left click: GTK Look\nRight click: Qt6ct",
            leftCommand: ["nwg-look"],
            rightCommand: ["qt6ct"]
        }
    ]

    property Item tooltipAnchor: null
    property string tooltipText: ""

    function launch(command) {
        if (command && command.length > 0)
            Quickshell.execDetached(command);
    }

    function showTooltip(anchorItem, text) {
        root.tooltipAnchor = anchorItem;
        root.tooltipText = text;
        tooltipDelay.restart();
    }

    function hideTooltip(anchorItem) {
        if (root.tooltipAnchor !== anchorItem)
            return;

        tooltipDelay.stop();
        launcherTooltip.visible = false;
        root.tooltipAnchor = null;
    }

    spacing: 0

    Item {
        implicitWidth: root.expanded ? launcherRow.implicitWidth + root.drawerGap : 0
        implicitHeight: toggleText.implicitHeight

        clip: true
        opacity: root.expanded ? 1 : 0

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }

        RowLayout {
            id: launcherRow

            anchors.rightMargin: root.drawerGap
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: root.launchers

                delegate: Text {
                    id: launcherButton

                    required property var modelData

                    text: modelData.icon
                    color: launcherMouse.containsMouse ? root.theme.launcherHoverColor : root.theme.launcherColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.launcherFontSize
                        bold: true
                    }

                    MouseArea {
                        id: launcherMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onEntered: root.showTooltip(launcherButton, launcherButton.modelData.tooltip)
                        onExited: root.hideTooltip(launcherButton)

                        onClicked: mouse => {
                            root.hideTooltip(launcherButton);
                            const command = mouse.button === Qt.RightButton ? launcherButton.modelData.rightCommand : launcherButton.modelData.leftCommand;
                            root.launch(command);
                        }
                    }
                }
            }

            Timer {
                id: tooltipDelay
                interval: 300
                repeat: false
                onTriggered: launcherTooltip.visible = root.tooltipAnchor !== null
            }
        }
    }

    Item {
        implicitWidth: toggleText.implicitWidth
        implicitHeight: toggleText.implicitHeight

        Text {
            id: toggleText

            anchors.centerIn: parent
            text: root.checking ? " .." : " " + root.updateCount
            color: toggleHover.hovered ? root.theme.launcherHoverColor : (root.updateCount > 0 ? root.theme.launcherColor : root.theme.launcherEmptyColor)
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.launcherFontSize
                bold: true
            }
        }

        HoverHandler {
            id: toggleHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.updateRequested()
        }
    }

    PopupWindow {
        id: launcherTooltip

        visible: false
        color: "transparent"
        grabFocus: false

        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 16

        anchor.item: root.tooltipAnchor ? root.tooltipAnchor : toggleText
        anchor.rect.x: 0
        anchor.rect.y: -8
        anchor.rect.width: root.tooltipAnchor ? root.tooltipAnchor.width : toggleText.width
        anchor.rect.height: root.tooltipAnchor ? root.tooltipAnchor.height : toggleText.height
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top

        Rectangle {
            anchors.fill: parent
            color: root.theme.tooltipBg
            border.color: root.theme.tooltipBorderColor
            border.width: 1
            radius: root.theme.radiusMedium

            Text {
                id: tooltipLabel

                anchors.centerIn: parent
                text: root.tooltipText
                color: root.theme.tooltipColor
                horizontalAlignment: Text.AlignHCenter
                font {
                    family: root.theme.tooltipFontFamily
                    pixelSize: root.theme.tooltipFontSize
                }
            }
        }
    }
}
