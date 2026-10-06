pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var colors
    required property var service
    property string selectedFamily: ""
    signal familySelected(string family)
    spacing: 10
    readonly property var families: [
        { family: "ge", label: "GE-Proton", variant: "x86-64" },
        { family: "cachyos", label: "CachyOS Proton", variant: "SLR · x86-64-v3" }
    ]
    Repeater {
        model: root.families
        Section {
            id: familyCard
            required property var modelData
            colors: root.colors
            readonly property var release: root.service.snapshot?.releases[modelData.family] ?? null
            readonly property var installed: root.service.snapshot?.installations.filter(item => item.family === modelData.family) ?? []
            readonly property bool selected: root.selectedFamily === modelData.family
            readonly property bool upToDate: release !== null && installed.some(item => item.name === release.name)
            implicitHeight: familyContent.implicitHeight + 24
            color: familyHover.containsMouse ? root.colors.cardHover : root.colors.card
            border.color: selected ? root.colors.selectedBorder : root.colors.border
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.label + " " + modelData.variant
            Accessible.checked: selected
            Keys.onSpacePressed: root.familySelected(familyCard.modelData.family)
            Keys.onReturnPressed: root.familySelected(familyCard.modelData.family)
            MouseArea {
                id: familyHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { familyCard.forceActiveFocus(); root.familySelected(familyCard.modelData.family); }
            }
            ColumnLayout {
                id: familyContent
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 6
                RowLayout {
                    Label {
                        theme: root.theme; colors: root.colors
                        text: familyCard.modelData.label + " <span style=\"font-size: 11px; font-weight: normal; color: " + root.colors.dimText + "\">(" + familyCard.modelData.variant + ")</span>"
                        textFormat: Text.RichText
                        font.bold: true
                    }
                    Label {
                        theme: root.theme; colors: root.colors
                        Layout.fillWidth: false
                        text: !familyCard.release ? "Unavailable" : familyCard.upToDate ? "Up to date" : familyCard.installed.length ? "Update available" : "Not installed"
                        color: !familyCard.release ? root.colors.secondary : familyCard.upToDate ? root.colors.success : root.colors.warning
                        font.pixelSize: 12
                    }
                }
                RowLayout {
                    Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: "Newest installed"; color: root.colors.dimText }
                    Label { theme: root.theme; colors: root.colors; text: familyCard.installed[0]?.name ?? "—"; horizontalAlignment: Text.AlignRight; color: root.colors.dimText }
                }
                RowLayout {
                    Label { theme: root.theme; colors: root.colors; Layout.fillWidth: false; text: "Latest"; color: root.colors.dimText }
                    Label { theme: root.theme; colors: root.colors; text: familyCard.release?.name ?? "—"; horizontalAlignment: Text.AlignRight; color: root.colors.dimText }
                }
            }
        }
    }
    Messages {
        theme: root.theme; colors: root.colors
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        entries: (root.service.snapshot?.messages.updates ?? []).concat(root.service.messages.updates)
    }
}
