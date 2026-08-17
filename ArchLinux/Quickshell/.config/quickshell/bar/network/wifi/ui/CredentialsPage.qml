import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "./controls"

// Renders personal or enterprise credentials and connection actions.
ColumnLayout {
    id: root

    required property var controller
    required property var style

    spacing: 12

    Label {
        text: root.controller.targetIsEnterprise ? ("Log in to " + root.controller.targetSsid) : ("Password for " + root.controller.targetSsid)
        color: root.style.foreground
        font.family: root.style.textFont
        font.pixelSize: 14
        font.weight: 600
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    PillField {
        id: userField

        style: root.style
        visible: root.controller.targetIsEnterprise
        Layout.fillWidth: true
        placeholder: "Username"
        text: root.controller.enteredUser
        enabled: !root.controller.isBusy
        onTextChanged: root.controller.enteredUser = text
        onAccepted: passField.forceActiveFocus()
    }

    PillField {
        id: passField

        style: root.style
        Layout.fillWidth: true
        placeholder: "Password"
        echoMode: TextInput.Password
        text: root.controller.enteredPass
        enabled: !root.controller.isBusy
        onTextChanged: root.controller.enteredPass = text
        onAccepted: root.controller.submitCredentials()
    }

    RowLayout {
        spacing: 10
        Layout.fillWidth: true

        MenuButton {
            style: root.style
            Layout.fillWidth: true
            height: 40
            text: "Back"
            icon: "󰁍"
            disabled: root.controller.isBusy
            onClicked: root.controller.showNetworkList()
        }

        MenuButton {
            style: root.style
            Layout.fillWidth: true
            height: 40
            text: root.controller.isBusy ? "Connecting…" : "Connect"
            textColor: "#1e2326"
            icon: "󱄙"
            kind: "primary"
            disabled: root.controller.isBusy
            onClicked: root.controller.submitCredentials()
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

    /* Credential requests arrive after controller page state changes. Defer focus
       until StackLayout exposes this page, then route enterprise users to username. */
    Connections {
        target: root.controller

        function onCredentialsRequested(focusUsername) {
            Qt.callLater(() => {
                if (focusUsername)
                    userField.forceActiveFocus();
                else
                    passField.forceActiveFocus();
            });
        }
    }
}
