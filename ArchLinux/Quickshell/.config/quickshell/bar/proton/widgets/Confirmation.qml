import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as Proton

Item {
    id: root
    required property var theme
    required property var colors
    property var descriptor: null
    property bool busy: false
    signal confirmRequested
    signal cancelRequested
    readonly property bool removing: descriptor?.action === "remove"
    implicitHeight: confirmationContent.implicitHeight + 56
    visible: descriptor !== null
    clip: true
    z: 10
    Rectangle {
        anchors.fill: parent
        color: root.colors.dimOverlay
        radius: 8
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: root.cancelRequested()
        onWheel: event => event.accepted = true
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(0, Math.min(440, parent.width - 24))
        height: Math.max(0, Math.min(confirmationContent.implicitHeight + 32, parent.height - 24))
        color: Qt.rgba(root.colors.tab.r, root.colors.tab.g, root.colors.tab.b, root.colors.manager.a)
        border.color: root.colors.confirmationBorder
        radius: 8
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
        ScrollView {
            id: confirmationScroll
            anchors.fill: parent
            anchors.margins: 16
            contentWidth: availableWidth
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: confirmationContent
                width: confirmationScroll.availableWidth
                spacing: 12
                Proton.Label {
                    theme: root.theme
                    colors: root.colors
                    text: root.removing ? "Confirm removal" : "Confirm cleanup"
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                }
                Proton.Label {
                    theme: root.theme
                    colors: root.colors
                    text: (root.removing ? "Remove " : "Install ") + (root.descriptor?.target.name ?? "")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.colors.confirmationText
                }
                Proton.Label {
                    theme: root.theme
                    colors: root.colors
                    visible: !root.removing && root.descriptor?.target.family === "ge"
                    text: "Switch umu to the new GE version."
                    horizontalAlignment: Text.AlignHCenter
                    color: root.colors.confirmationText
                }
                Proton.Label {
                    theme: root.theme
                    colors: root.colors
                    visible: !root.removing
                    text: "Remove:\n" + (root.descriptor?.cleanupCandidates.map(item => item.name).join("\n") || "No older versions")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.colors.cleanupText
                }
                Proton.Label {
                    theme: root.theme
                    colors: root.colors
                    text: "Steam games assigned to removed versions may need their compatibility setting changed."
                    horizontalAlignment: Text.AlignHCenter
                    color: root.colors.warning
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    Layout.bottomMargin: 1
                    Proton.Action {
                        theme: root.theme
                        colors: root.colors
                        text: "Confirm"
                        enabled: !root.busy
                        onClicked: root.confirmRequested()
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Proton.Action {
                        theme: root.theme
                        colors: root.colors
                        text: "Cancel"
                        enabled: !root.busy
                        onClicked: root.cancelRequested()
                    }
                }
            }
        }
    }
}
