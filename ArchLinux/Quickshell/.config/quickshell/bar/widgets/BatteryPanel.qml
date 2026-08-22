pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core as Core

PopupWindow {
    id: root

    required property Item anchorItem
    required property string icon
    required property bool available
    required property int capacity
    required property string status
    required property bool acOnline
    required property real energyFullUwh
    required property real energyFullDesignUwh
    required property int cycleCount
    required property int chargeStartThreshold
    required property int chargeEndThreshold
    required property string activePowerProfile
    required property bool actionBusy
    required property string actionError
    required property Core.Theme theme

    signal powerProfileRequested(string profile)
    signal chargeThresholdsRequested(int startValue, int endValue)

    property int pendingStartThreshold: 45
    property int pendingEndThreshold: 50
    property bool limitsEdited: false
    readonly property bool limitsChanged: root.pendingStartThreshold !== root.chargeStartThreshold || root.pendingEndThreshold !== root.chargeEndThreshold

    function resetPendingThresholds() {
        let start = root.chargeStartThreshold >= 0 ? Math.round(root.chargeStartThreshold / 5) * 5 : 45;
        let end = root.chargeEndThreshold >= 0 ? Math.round(root.chargeEndThreshold / 5) * 5 : 50;
        start = Math.max(45, Math.min(95, start));
        end = Math.max(50, Math.min(100, end));
        if (end <= start) {
            if (start < 100)
                end = start + 5;
            else {
                start = 95;
                end = 100;
            }
        }
        root.pendingStartThreshold = start;
        root.pendingEndThreshold = end;
        root.limitsEdited = false;
    }

    function syncPendingThresholds() {
        if (!root.visible)
            return;
        const applied = root.chargeStartThreshold === root.pendingStartThreshold && root.chargeEndThreshold === root.pendingEndThreshold;
        if (!root.limitsEdited || applied)
            root.resetPendingThresholds();
    }

    function batterySizeText() {
        if (root.energyFullUwh < 0)
            return "N/A";
        return (root.energyFullUwh / 1000000).toFixed(1).replace(/\.0$/, "") + " Wh";
    }

    function batteryHealthText() {
        if (root.energyFullUwh < 0 || root.energyFullDesignUwh <= 0)
            return "N/A";
        const health = Math.round(root.energyFullUwh * 100 / root.energyFullDesignUwh);
        return Math.max(0, Math.min(100, health)) + "%";
    }

    function batteryStateText() {
        if (!root.available)
            return "Unavailable";
        if (root.acOnline && root.status === "Not charging")
            return "Holding";
        return root.status;
    }

    component ThresholdButton: Button {
        id: control

        required property string glyph
        required property bool canChange

        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        enabled: control.canChange && !root.actionBusy

        contentItem: Text {
            text: control.glyph
            color: control.enabled ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelMutedColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font {
                family: root.theme.fontFamily
                pixelSize: root.theme.batteryPanelHeaderFontSize
                bold: true
            }
        }

        background: Rectangle {
            color: control.hovered && control.enabled ? Qt.lighter(root.theme.batteryPanelInactiveButtonColor, 1.2) : root.theme.batteryPanelInactiveButtonColor
            border.color: control.enabled ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelBorderColor
            border.width: 1
            radius: 4
        }

        HoverHandler {
            cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    visible: false
    color: "transparent"
    grabFocus: true
    implicitWidth: 450
    implicitHeight: panelContent.implicitHeight + 32

    onVisibleChanged: {
        if (visible)
            root.resetPendingThresholds();
    }
    onChargeStartThresholdChanged: Qt.callLater(root.syncPendingThresholds)
    onChargeEndThresholdChanged: Qt.callLater(root.syncPendingThresholds)

    anchor.item: root.anchorItem
    anchor.rect.x: 9
    anchor.rect.y: -8
    anchor.rect.width: root.anchorItem.width
    anchor.rect.height: root.anchorItem.height
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    Rectangle {
        anchors.fill: parent
        color: root.theme.batteryPanelBackgroundColor
        border.color: root.theme.batteryPanelBorderColor
        border.width: 1
        radius: root.theme.radiusMedium

        ColumnLayout {
            id: panelContent

            anchors.fill: parent
            anchors.margins: 16
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.icon
                    color: root.theme.batteryPanelHeaderColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.batteryPanelHeaderFontSize
                        bold: true
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "Battery"
                        color: root.theme.batteryPanelTextColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize + 4
                            bold: true
                        }
                    }

                    Text {
                        text: root.batteryStateText().toUpperCase()
                        color: root.theme.batteryPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize
                            bold: true
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: root.available ? root.capacity + "%" : "N/A"
                    color: root.theme.batteryPanelAccentColor
                    font {
                        family: root.theme.fontFamily
                        pixelSize: root.theme.batteryPanelHeaderFontSize + 8
                        bold: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                radius: height / 2
                color: root.theme.batteryPanelTrackColor

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, root.capacity)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.theme.batteryPanelAccentColor
                    visible: root.available
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 24
                rowSpacing: 7

                Repeater {
                    model: [
                        {
                            label: "Battery size",
                            value: root.batterySizeText()
                        },
                        {
                            label: "Battery health",
                            value: root.batteryHealthText()
                        },
                        {
                            label: "Charge cycles",
                            value: root.cycleCount >= 0 ? root.cycleCount.toString() : "N/A"
                        },
                        {
                            label: "Battery state",
                            value: root.batteryStateText()
                        }
                    ]

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: parent.modelData.label
                            color: root.theme.batteryPanelMutedColor
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            text: parent.modelData.value
                            color: root.theme.batteryPanelTextColor
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                                bold: true
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.batteryPanelBorderColor
                opacity: 0.16
            }

            Text {
                text: "POWER PROFILE"
                color: root.theme.batteryPanelMutedColor
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.batteryPanelFontSize
                    bold: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        {
                            label: "󰌪  Power-saver",
                            value: "power-saver"
                        },
                        {
                            label: "󰾅  Balanced",
                            value: "balanced"
                        },
                        {
                            label: "󰓅  Performance",
                            value: "performance"
                        }
                    ]

                    delegate: Button {
                        id: profileButton
                        required property var modelData

                        Layout.fillWidth: true
                        enabled: !root.actionBusy
                        onClicked: root.powerProfileRequested(modelData.value)

                        contentItem: Text {
                            text: profileButton.modelData.label
                            color: root.activePowerProfile === profileButton.modelData.value ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelInactiveButtonTextColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                                bold: root.activePowerProfile === profileButton.modelData.value
                            }
                        }

                        background: Rectangle {
                            color: root.activePowerProfile === profileButton.modelData.value ? root.theme.batteryPanelActiveButtonColor : profileButton.hovered ? Qt.lighter(root.theme.batteryPanelInactiveButtonColor, 1.2) : root.theme.batteryPanelInactiveButtonColor
                            border.color: root.activePowerProfile === profileButton.modelData.value ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelBorderColor
                            border.width: 1
                            radius: 4
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.theme.batteryPanelBorderColor
                opacity: 0.16
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "CHARGE LIMIT"
                        color: root.theme.batteryPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize
                            bold: true
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "5% steps"
                        color: root.theme.batteryPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.preferredWidth: 40
                        text: "START"
                        color: root.theme.batteryPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize
                            bold: true
                        }
                    }

                    ThresholdButton {
                        glyph: "−"
                        canChange: root.pendingStartThreshold > 45
                        onClicked: {
                            root.pendingStartThreshold -= 5;
                            root.limitsEdited = true;
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 30
                        color: root.theme.batteryPanelActiveButtonColor
                        border.color: root.theme.batteryPanelBorderColor
                        border.width: 1
                        radius: 4

                        Text {
                            anchors.centerIn: parent
                            text: root.pendingStartThreshold + "%"
                            color: root.theme.batteryPanelAccentColor
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                                bold: true
                            }
                        }
                    }

                    ThresholdButton {
                        glyph: "+"
                        canChange: root.pendingStartThreshold < 95 && root.pendingStartThreshold + 5 < root.pendingEndThreshold
                        onClicked: {
                            root.pendingStartThreshold += 5;
                            root.limitsEdited = true;
                        }
                    }

                    Item {
                        Layout.preferredWidth: 12
                    }

                    Text {
                        Layout.preferredWidth: 26
                        text: "END"
                        color: root.theme.batteryPanelMutedColor
                        font {
                            family: root.theme.fontFamily
                            pixelSize: root.theme.batteryPanelFontSize
                            bold: true
                        }
                    }

                    ThresholdButton {
                        glyph: "−"
                        canChange: root.pendingEndThreshold > 50 && root.pendingEndThreshold - 5 > root.pendingStartThreshold
                        onClicked: {
                            root.pendingEndThreshold -= 5;
                            root.limitsEdited = true;
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 30
                        color: root.theme.batteryPanelActiveButtonColor
                        border.color: root.theme.batteryPanelBorderColor
                        border.width: 1
                        radius: 4

                        Text {
                            anchors.centerIn: parent
                            text: root.pendingEndThreshold + "%"
                            color: root.theme.batteryPanelAccentColor
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                                bold: true
                            }
                        }
                    }

                    ThresholdButton {
                        glyph: "+"
                        canChange: root.pendingEndThreshold < 100
                        onClicked: {
                            root.pendingEndThreshold += 5;
                            root.limitsEdited = true;
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        id: applyButton

                        Layout.preferredHeight: 30
                        enabled: root.chargeStartThreshold >= 0 && root.chargeEndThreshold >= 0 && root.limitsChanged && root.pendingStartThreshold >= 45 && root.pendingStartThreshold <= 95 && root.pendingEndThreshold >= 50 && root.pendingEndThreshold <= 100 && root.pendingEndThreshold > root.pendingStartThreshold && !root.actionBusy
                        onClicked: root.chargeThresholdsRequested(root.pendingStartThreshold, root.pendingEndThreshold)

                        contentItem: Text {
                            text: root.actionBusy ? "Applying…" : "Apply"
                            color: applyButton.enabled ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelMutedColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font {
                                family: root.theme.fontFamily
                                pixelSize: root.theme.batteryPanelFontSize
                                bold: true
                            }
                        }

                        background: Rectangle {
                            color: applyButton.hovered && applyButton.enabled ? Qt.lighter(root.theme.batteryPanelInactiveButtonColor, 1.2) : root.theme.batteryPanelInactiveButtonColor
                            border.color: applyButton.enabled ? root.theme.batteryPanelAccentColor : root.theme.batteryPanelBorderColor
                            border.width: 1
                            radius: 4
                        }

                        HoverHandler {
                            cursorShape: applyButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.actionError !== ""
                text: root.actionError
                color: root.theme.batteryPanelErrorColor
                horizontalAlignment: Text.AlignRight
                font {
                    family: root.theme.fontFamily
                    pixelSize: root.theme.batteryPanelFontSize
                }
            }
        }
    }
}
