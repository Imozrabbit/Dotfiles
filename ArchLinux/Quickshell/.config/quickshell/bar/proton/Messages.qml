pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var colors
    property var entries: []
    Layout.fillWidth: true
    visible: entries.length > 0
    spacing: 6
    Repeater {
        model: root.entries
        Label {
            required property var modelData
            theme: root.theme
            colors: root.colors
            text: modelData.text
            horizontalAlignment: Text.AlignHCenter
            color: modelData.severity === "error" ? root.colors.error : modelData.severity === "warning" ? root.colors.warning : modelData.severity === "success" ? root.colors.success : root.colors.secondary
        }
    }
}
