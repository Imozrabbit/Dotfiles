import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Renders the WiFi menu action button and emits click intent.
Rectangle {
    id: root

    required property var style

    property string text: ""
    property string icon: ""
    property string kind: "outline"
    property bool disabled: false
    property bool compact: false
    property color btnColor: style.success
    property color textColor: kind === "primary" ? style.background : style.foreground

    signal clicked

    readonly property bool hovered: mouse.containsMouse

    radius: 12
    implicitHeight: compact ? 24 : 40
    scale: mouse.pressed ? 0.95 : (hovered && !disabled ? 1.045 : 1.0)
    color: {
        if (kind === "primary") {
            if (disabled)
                return Qt.rgba(btnColor.r, btnColor.g, btnColor.b, 0.35);
            return hovered ? Qt.darker(btnColor, 1.1) : btnColor;
        }
        return hovered ? Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.10) : "transparent";
    }
    border.width: (kind === "primary" || kind === "ghost") ? 0 : 1
    border.color: {
        return kind === "primary" ? "transparent" : (hovered ? Qt.rgba(style.accent.r, style.accent.g, style.accent.b, 0.35) : style.border);
    }
    opacity: disabled ? 0.55 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutBack
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 120
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: root.compact ? 4 : 8

        Label {
            visible: root.icon.length > 0
            text: root.icon
            font.family: root.style.iconFont
            font.pixelSize: root.compact ? 12 : 16
            color: root.textColor
        }

        Label {
            text: root.text
            font.family: root.style.textFont
            font.pixelSize: root.compact ? 11 : 13
            font.weight: root.compact ? Font.Normal : Font.DemiBold
            color: root.textColor
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !root.disabled
        onClicked: root.clicked()
    }
}
