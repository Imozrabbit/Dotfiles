pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../components/tooltips"
import "../common/Theme.js" as Theme

ActionTile {
    id: root

    property string presentation: "icon"
    property string title: ""
    property string details: ""
    property var tooltipOn: null
    property var tooltipOff: null
    property bool toggleAction: root.checkable
    property string statusHint: ""
    readonly property bool detailed: presentation === "details"
    readonly property string hintText: {
        const label = root.tooltip || root.title;
        if (root.statusHint !== "")
            return (label ? label + ": " : "") + root.statusHint;
        if (!root.toggleAction)
            return label;
        const custom = root.checked ? root.tooltipOn : root.tooltipOff;
        return typeof custom === "string" ? custom : label ? (root.checked ? "Disable " : "Enable ") + label : "";
    }

    implicitHeight: 36
    highlightChecked: !root.detailed
    Accessible.name: [root.title || root.tooltip || root.glyph, root.details].filter(text => text !== "").join(", ")
    Accessible.checkable: root.toggleAction
    Accessible.checked: root.checked
    Accessible.description: "UI preview only"
    ActionToolTip {
        control: root
        themeColors: root.themeColors
        text: root.hintText
        showWhenDisabled: root.statusHint !== ""
    }

    component MarqueeLine: Item {
        id: line
        property string text: ""
        required property color textColor
        property int pixelSize: 10
        property int weight: Font.Normal
        property bool animate: false
        readonly property real overflow: Math.max(0, label.implicitWidth - width)

        height: label.implicitHeight
        clip: true
        onOverflowChanged: {
            if (marquee.running)
                marquee.restart();
        }

        Text {
            id: label
            objectName: line.objectName + "Text"
            text: line.text
            color: line.textColor
            font.family: Theme.textFont
            font.pixelSize: line.pixelSize
            font.weight: line.weight
            textFormat: Text.PlainText
            wrapMode: Text.NoWrap
        }

        SequentialAnimation {
            id: marquee
            running: line.animate && line.visible && line.enabled && line.overflow > 0
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    label.x = 0;
            }
            PauseAnimation {
                duration: 700
            }
            NumberAnimation {
                target: label
                property: "x"
                from: 0
                to: -line.overflow
                duration: Math.max(300, line.overflow / 30 * 1000)
            }
            PauseAnimation {
                duration: 700
            }
            NumberAnimation {
                target: label
                property: "x"
                from: -line.overflow
                to: 0
                duration: Math.max(300, line.overflow / 30 * 1000)
            }
        }
    }

    contentItem: Item {
        id: content
        clip: true

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.detailed ? 8 : (parent.width - width) / 2
            width: 26
            height: 26
            radius: 8
            color: root.detailed ? (root.checked ? root.themeColors.tileActive : root.themeColors.gridTileHover) : "transparent"

            FontMetrics {
                id: iconMetrics
                font: icon.font
                readonly property rect ink: tightBoundingRect(root.glyph)
            }

            Text {
                id: icon
                objectName: "quickGlyph"
                anchors.fill: parent
                // Center the painted glyph, not its font advance/line box.
                leftPadding: Math.max(0, (width - iconMetrics.ink.width) / 2 - iconMetrics.ink.x)
                topPadding: Math.max(0, (height - iconMetrics.ink.height) / 2 - iconMetrics.ascent - iconMetrics.ink.y)
                text: root.glyph
                color: root.enabled ? root.iconColor : Qt.darker(root.iconColor, 1.5)
                font.family: Theme.iconFont
                font.pixelSize: 16
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
                clip: true
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            x: 42
            width: Math.max(0, content.width - x - 8)
            spacing: 1
            visible: root.detailed
            opacity: root.enabled ? 1 : 0.5

            MarqueeLine {
                objectName: "quickTitle"
                width: parent.width
                text: root.title
                textColor: root.themeColors.text
                pixelSize: 12
                weight: Font.DemiBold
                animate: root.hovered
            }
            MarqueeLine {
                objectName: "quickDetails"
                width: parent.width
                text: root.details
                textColor: root.themeColors.text
                opacity: 0.8
                animate: root.hovered
            }
        }
    }
}
