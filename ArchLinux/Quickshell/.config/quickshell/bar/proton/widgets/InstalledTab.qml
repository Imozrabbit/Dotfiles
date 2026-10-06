pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var colors
    required property var service
    property string expandedVersion: ""
    spacing: 10
    function toggleVersion(name) { root.expandedVersion = root.expandedVersion === name ? "" : name; }
    Repeater {
        model: root.service.snapshot?.installations ?? []
        Rectangle {
            id: installedEntry
            required property var modelData
            readonly property bool expanded: root.expandedVersion === modelData.name
            Layout.fillWidth: true
            implicitHeight: installedContent.implicitHeight + 24
            color: expanded ? root.colors.card : installedMouse.containsMouse ? root.colors.installedHover : "transparent"
            border.width: expanded ? 1 : 0
            border.color: root.colors.border
            radius: 8
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name + (modelData.umuSelected ? ", umu selected" : "")
            Keys.onSpacePressed: root.toggleVersion(installedEntry.modelData.name)
            Keys.onReturnPressed: root.toggleVersion(installedEntry.modelData.name)
            MouseArea {
                id: installedMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { installedEntry.forceActiveFocus(); root.toggleVersion(installedEntry.modelData.name); }
            }
            ColumnLayout {
                id: installedContent
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8
                RowLayout {
                    Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: "•"; color: root.colors.dimText; font.pixelSize: 13 }
                    Label { theme: root.theme; colors: root.colors; text: installedEntry.modelData.name; font.pixelSize: 13 }
                    Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; visible: installedEntry.modelData.umuSelected; text: "umu"; color: root.colors.umu; font.pixelSize: 12 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: installedEntry.expanded
                    spacing: 8
                    Label {
                        theme: root.theme; colors: root.colors
                        text: installedEntry.modelData.family === "ge" ? "GE-Proton (x86-64)" : "CachyOS Proton (SLR · x86-64-v3)"
                        color: root.colors.dimText
                        font.pixelSize: 12
                    }
                    Label {
                        theme: root.theme; colors: root.colors
                        text: "Installation directory\n" + installedEntry.modelData.path
                        color: root.colors.secondary
                        font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Action {
                            id: removeAction
                            theme: root.theme; colors: root.colors
                            text: ""
                            flat: true
                            enabled: !root.service.busy
                            Accessible.name: "Remove " + installedEntry.modelData.name
                            onClicked: root.service.prepareRemove(installedEntry.modelData.name)
                            contentItem: Text {
                                text: removeAction.text
                                color: removeAction.down ? root.colors.removePressed : removeAction.hovered ? root.colors.removeHover : root.colors.error
                                opacity: removeAction.enabled ? 1 : 0.55
                                font.family: root.theme.fontFamily
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }
    Messages {
        theme: root.theme; colors: root.colors
        Layout.bottomMargin: 5
        entries: (root.service.snapshot?.messages.installed ?? []).concat(
            root.service.snapshot && root.service.snapshot.installations.length === 0 && root.service.snapshot.messages.installed.length === 0 ? [{severity:"info",text:"No custom Proton versions installed."}] : [],
            root.service.messages.installed)
    }
}
