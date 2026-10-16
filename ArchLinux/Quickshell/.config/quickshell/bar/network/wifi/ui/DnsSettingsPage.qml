pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Saved profile policy is the only source of selection state.
ColumnLayout {
    id: root

    required property var style
    required property string profileUuid
    readonly property string selectedPolicy: root.record.policy || ""
    required property var backend
    property bool isHome: false
    readonly property bool homeLocked: root.isHome || root.record.home === true
    readonly property var record: root.backend ? root.backend.profiles[root.profileUuid] || ({}) : ({})

    spacing: 6
    onProfileUuidChanged: root.reload()
    onVisibleChanged: {
        if (visible)
            root.reload();
    }

    function reload() {
        if (root.backend && root.visible && root.profileUuid !== "")
            root.backend.load(root.profileUuid);
    }
    Connections {
        target: root.backend
        function onReadyChanged() {
            if (root.backend.ready)
                root.reload();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Label {
            text: "DNS"
            font.family: root.style.textFont
            font.pixelSize: 12
            font.bold: true
            color: root.style.foreground
        }

        Rectangle {
            visible: !root.homeLocked
            Layout.fillWidth: true
            implicitHeight: optionFlow.implicitHeight + 6
            radius: 8
            color: "transparent"
            border.color: root.style.border

            Flow {
                id: optionFlow
                x: 3
                y: 3
                width: parent.width - 6
                spacing: 3

                Repeater {
                    model: [
                        {
                            policy: "automatic",
                            label: "Default",
                            name: "automaticChoice"
                        }
                    ].concat(root.backend ? root.backend.providers.map(provider => ({
                                policy: provider.id,
                                label: provider.label,
                                name: provider.id + "Choice"
                            })) : [])
                    Button {
                        id: segment
                        required property var modelData
                        objectName: modelData.name
                        text: modelData.label
                        width: Math.max(60, (optionFlow.width - optionFlow.spacing) / 2)
                        height: 26
                        checkable: true
                        autoExclusive: true
                        checked: root.selectedPolicy === modelData.policy
                        enabled: !root.homeLocked && root.backend && root.backend.ready && !root.backend.busy && !!root.record.policy
                        onClicked: {
                            root.backend.save(root.profileUuid, modelData.policy);
                            segment.checked = Qt.binding(() => root.selectedPolicy === segment.modelData.policy);
                        }
                        padding: 0
                        font.family: root.style.textFont
                        font.pixelSize: 12
                        Accessible.name: "DNS: " + text

                        contentItem: Label {
                            text: segment.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: segment.checked ? root.style.foreground : root.style.muted
                            font: segment.font
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 5
                            color: segment.checked ? Qt.rgba(root.style.accent.r, root.style.accent.g, root.style.accent.b, 0.22) : segment.hovered ? Qt.rgba(root.style.accent.r, root.style.accent.g, root.style.accent.b, 0.08) : "transparent"
                            border.width: segment.visualFocus ? 1 : 0
                            border.color: root.style.accent
                        }
                    }
                }
            }
        }
        Label {
            visible: root.homeLocked
            Layout.fillWidth: true
            text: root.backend && (root.record.error || root.record.policy !== "automatic") ? "Router DNS required" : "Router DNS (automatic)"
            color: root.style.foreground
            font.family: root.style.textFont
            font.pixelSize: 12
        }
    }
    Flow {
        Layout.fillWidth: true
        visible: !!root.backend && !root.homeLocked
        spacing: 4
        Repeater {
            model: root.backend ? root.backend.providers : []
            Button {
                required property var modelData
                text: "Test " + modelData.label
                enabled: root.backend.ready && !root.backend.busy
                onClicked: root.backend.test(root.profileUuid, modelData.id)
                font.family: root.style.textFont
                font.pixelSize: 11
            }
        }
    }
    Label {
        Layout.fillWidth: true
        visible: !!root.backend && root.backend.configWarning !== ""
        text: root.backend ? root.backend.configWarning : ""
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        font.family: root.style.textFont
        font.pixelSize: 11
        color: root.style.error
    }
    Label {
        Layout.fillWidth: true
        text: root.record.message || ""
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: root.style.textFont
        font.pixelSize: 11
        color: root.record.error ? root.style.error : root.style.muted
    }
}
