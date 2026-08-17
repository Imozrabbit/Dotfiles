import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

import "./controls"

// Renders saved and available network lists and their list-level actions.
ColumnLayout {
    id: root

    required property var controller
    required property var style

    spacing: 10

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 86
        visible: !root.controller.scanRunning && root.controller.savedModel.count === 0 && root.controller.networkModel.count === 0

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            Label {
                text: "No networks found"
                font.family: root.style.textFont
                font.pixelSize: 13
                font.weight: 400
                color: root.style.foreground
            }

            Label {
                text: "Try rescan."
                font.family: root.style.textFont
                font.pixelSize: 11
                color: root.style.muted
            }

            MenuButton {
                style: root.style
                height: 34
                text: "Rescan"
                icon: "󰑓"
                disabled: root.controller.scanRunning || root.controller.isBusy
                onClicked: root.controller.rescanNow()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
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
        text: "Available"
        font.family: root.style.textFont
        font.pixelSize: 12
        font.weight: 600
        color: root.style.muted
        visible: root.controller.availableModel.count > 0
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(280, Math.max(0, root.controller.availableModel.count * 48))
        visible: root.controller.availableModel.count > 0
        clip: true
        model: root.controller.availableModel
        spacing: 6
        ScrollBar.vertical: ScrollBar {
            active: true
            width: 4
        }
        delegate: AvailableNetworkRow {
            style: root.style
            isBusy: root.controller.isBusy
            onSelected: (ssid, security, isEnterprise) => root.controller.selectNetwork(ssid, security, isEnterprise)
        }
    }

    MenuButton {
        style: root.style
        Layout.fillWidth: true
        height: 38
        text: "Open Advanced Settings"
        icon: "󰒓"
        kind: "ghost"
        disabled: root.controller.isBusy
        onClicked: root.controller.openAdvancedEditor()
    }
}
