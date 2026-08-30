import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

import "./controls"

/* Composes summary, feedback, and pages into complete WiFi card. Overlay owner
   remains responsible for bottom-right anchoring and outside-click handling. */
Item {
    id: root

    required property var controller
    required property var style

    implicitWidth: 390
    implicitHeight: Math.ceil(mainLayout.implicitHeight + 24)
    width: implicitWidth
    height: implicitHeight

    Behavior on height {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: menuCard
        color: root.style.card
        radius: root.style.radius
        layer.enabled: true
        layer.effect: DropShadow {
            radius: 44
            samples: 64
            verticalOffset: 18
            color: Qt.rgba(0, 0, 0, 0.55)
        }
    }

    Rectangle {
        id: menuCard

        anchors.fill: parent
        color: root.style.card
        radius: root.style.radius
        border.width: 1
        border.color: root.style.border
        clip: true

        ColumnLayout {
            id: mainLayout

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 8

            MenuButton {
                style: root.style
                Layout.alignment: Qt.AlignCenter
                Layout.preferredWidth: 93
                Layout.preferredHeight: 26
                text: root.controller.isExpanded ? " Collapse" : "Networks"
                icon: root.controller.isExpanded ? "" : ""
                kind: "ghost"
                disabled: root.controller.isBusy
                onClicked: root.controller.startScanToggle()
            }

            ConnectionSummary {
                controller: root.controller
                style: root.style
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 5
                Layout.topMargin: 3
                Layout.bottomMargin: -5
                visible: root.controller.savedModel.count > 0

                Label {
                    text: "Saved"
                    font.family: root.style.textFont
                    font.pixelSize: 12
                    font.weight: 600
                    color: root.style.muted
                    Layout.fillWidth: true
                }

                BusyIndicator {
                    running: root.controller.scanRunning
                    visible: root.controller.scanRunning
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: root.style.success
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(210, Math.max(0, root.controller.savedModel.count * 48))
                visible: root.controller.savedModel.count > 0
                clip: true
                model: root.controller.savedModel
                spacing: 6
                ScrollBar.vertical: ScrollBar {
                    active: true
                    width: 4
                }
                delegate: SavedNetworkRow {
                    style: root.style
                    isBusy: root.controller.isBusy
                    onClicked: (uuid, ssid) => root.controller.connectSaved(uuid, ssid)
                }
            }

            Label {
                visible: root.controller.statusLine.length > 0
                text: root.controller.statusLine
                font.family: root.style.textFont
                font.pixelSize: 11
                color: root.controller.statusIsError ? root.style.error : root.style.muted
            }

            TextArea {
                visible: root.controller.errorVisible
                text: root.controller.errorText
                readOnly: true
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight + 20, 120)
                font.family: root.style.textFont
                font.pixelSize: 11
                color: root.style.error
                background: Rectangle {
                    radius: 12
                    color: Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.style.error.r, root.style.error.g, root.style.error.b, 0.25)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.style.border
                visible: root.controller.isExpanded
                opacity: 0.7
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: root.controller.isExpanded ? viewStack.children[viewStack.currentIndex].implicitHeight : 0
                visible: root.controller.isExpanded
                opacity: root.controller.isExpanded ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                    }
                }

                /* Controller owns page state; StackLayout only composes list and
                   credential pages while expanded height follows selected page. */
                StackLayout {
                    id: viewStack

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    currentIndex: root.controller.currentPage

                    NetworkListPage {
                        controller: root.controller
                        style: root.style
                    }

                    CredentialsPage {
                        controller: root.controller
                        style: root.style
                    }
                }
            }
        }
    }
}
