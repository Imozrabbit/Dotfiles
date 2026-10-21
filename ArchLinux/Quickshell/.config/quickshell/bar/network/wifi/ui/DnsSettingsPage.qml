pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "./controls"

// Selection is a draft; only Confirm writes the profile.
ColumnLayout {
    id: root

    required property var style
    required property string profileUuid
    readonly property string savedPolicy: root.record.policy || ""
    property string pendingPolicy: ""
    readonly property string selectedPolicy: root.pendingPolicy || root.savedPolicy
    readonly property bool dirty: root.selectedPolicy !== root.savedPolicy
    readonly property bool canAct: !!root.backend && root.backend.ready && !root.backend.busy && !root.homeLocked && !!root.savedPolicy
    readonly property bool providerSelected: !!root.backend && root.backend.providers.some(provider => provider.id === root.selectedPolicy)
    onSavedPolicyChanged: {
        if (root.pendingPolicy === root.savedPolicy)
            root.pendingPolicy = "";
    }
    onHomeLockedChanged: {
        if (root.homeLocked)
            root.pendingPolicy = "";
    }
    required property var backend
    property var observedDns: null
    readonly property string autoLabel: {
        const dns = root.observedDns;
        if (!dns)
            return "Auto · Network DNS";
        if (dns.kind === "unavailable")
            return "Auto · DNS unavailable";
        if (dns.kind === "mixed" || dns.source === "mixed")
            return "Auto · Mixed DNS";
        const source = dns.source === "vpn" ? "VPN DNS" : dns.source === "network" ? "Network DNS" : "DNS";
        return "Auto · " + source + (["nextdns", "quad9"].includes(dns.kind) ? ": " + dns.name : "");
    }
    property bool isHome: false
    readonly property bool homeLocked: root.isHome || root.record.home === true
    readonly property var record: root.backend ? root.backend.profiles[root.profileUuid] || ({}) : ({})

    spacing: 6
    FontMetrics {
        id: choiceMetrics
        font.family: root.style.textFont
        font.pixelSize: 12
    }
    onProfileUuidChanged: {
        root.pendingPolicy = "";
        root.reload();
    }
    onVisibleChanged: {
        root.pendingPolicy = "";
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

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: (root.homeLocked ? 30 : optionRows.implicitHeight) + 16
            radius: 8
            color: "transparent"
            border.color: root.style.border

            Label {
                id: dnsCaption
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "DNS"
                font.family: root.style.textFont
                font.pixelSize: 12
                font.bold: true
                color: root.style.foreground
            }

            Column {
                id: optionRows
                visible: !root.homeLocked
                x: dnsCaption.x + dnsCaption.implicitWidth + 6
                y: 8
                width: Math.max(0, parent.width - x - 4)
                spacing: 6
                readonly property var choices: [
                    {
                        policy: "automatic",
                        label: root.autoLabel,
                        name: "automaticChoice"
                    }
                ].concat(root.backend ? root.backend.providers.map(provider => ({
                            policy: provider.id,
                            label: provider.label,
                            name: provider.id + "Choice"
                        })) : [])
                readonly property var rows: {
                    const result = [];
                    let row = [];
                    let used = 0;
                    const available = Math.max(0, optionRows.width);
                    for (const choice of optionRows.choices) {
                        const item = Object.assign({}, choice, {
                            width: Math.min(available, Math.ceil(choiceMetrics.advanceWidth(choice.label)) + 20)
                        });
                        if (row.length && (row.length === 3 || used + optionRows.spacing + item.width > available)) {
                            result.push(row);
                            row = [];
                            used = 0;
                        }
                        used += (row.length ? optionRows.spacing : 0) + item.width;
                        row.push(item);
                    }
                    if (row.length)
                        result.push(row);
                    return result;
                }
                Repeater {
                    model: optionRows.rows
                    Row {
                        id: optionRow
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: optionRows.spacing

                        Repeater {
                            model: optionRow.modelData
                            Button {
                                id: segment
                                required property var modelData
                                objectName: modelData.name
                                text: modelData.policy === "automatic" ? root.autoLabel : modelData.label
                                width: modelData.width
                                height: 30
                                checkable: true
                                autoExclusive: true
                                checked: root.selectedPolicy === modelData.policy
                                enabled: root.canAct
                                onClicked: {
                                    if (root.canAct)
                                        root.pendingPolicy = modelData.policy === root.savedPolicy ? "" : modelData.policy;
                                    segment.checked = Qt.binding(() => root.selectedPolicy === segment.modelData.policy);
                                }
                                padding: 0
                                font: choiceMetrics.font
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
            }
            Label {
                objectName: "homeDnsStatus"
                visible: root.homeLocked
                x: optionRows.x
                width: optionRows.width
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.backend && (root.record.error || root.record.policy !== "automatic") ? "Router DNS required" : "Router DNS (automatic)"
                color: root.style.foreground
                font.family: root.style.textFont
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: !!root.backend && !root.homeLocked
        spacing: 4
        Item {
            Layout.fillWidth: true
        }
        Repeater {
            model: [
                {
                    id: "confirm",
                    label: "Confirm"
                },
                {
                    id: "test",
                    label: "Test"
                },
                {
                    id: "cancel",
                    label: "Cancel"
                }
            ]
            MenuButton {
                id: actionButton
                required property var modelData
                objectName: modelData.id + "Dns"
                style: root.style
                kind: "ghost"
                compact: true
                text: modelData.label
                implicitWidth: actionLabel.advanceWidth + 16
                height: 24
                disabled: {
                    if (!root.canAct)
                        return true;
                    if (modelData.id === "test")
                        return !root.providerSelected;
                    if (modelData.id === "confirm")
                        return !root.dirty || (root.selectedPolicy !== "automatic" && !root.providerSelected);
                    return !root.dirty;
                }
                enabled: !disabled
                textColor: hovered ? root.style.foreground : root.style.muted
                onClicked: {
                    if (disabled)
                        return;
                    if (modelData.id === "confirm")
                        root.backend.save(root.profileUuid, root.selectedPolicy);
                    else if (modelData.id === "test")
                        root.backend.test(root.profileUuid, root.selectedPolicy);
                    else
                        root.pendingPolicy = "";
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label + " DNS choice"
                Accessible.onPressAction: {
                    if (!disabled)
                        clicked();
                }

                TextMetrics {
                    id: actionLabel
                    text: actionButton.text
                    font.family: root.style.textFont
                    font.pixelSize: 11
                    font.weight: Font.Normal
                }
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
