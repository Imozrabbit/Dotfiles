pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../components/tooltips"
import "../common/Theme.js" as Theme

Item {
    id: root

    property var actions: []
    property var themeColors: Theme.colors
    signal actionRequested(string action)

    readonly property var visibleActions: root.actions.filter(action => action.enabled !== false)
    readonly property int columns: Math.max(1, Math.floor((width + 6) / 38))
    readonly property var definitions: ({
            poweroff: {
                glyph: "󰐥",
                label: "Power off",
                colorRole: "danger"
            },
            reboot: {
                glyph: "󰜉",
                label: "Reboot",
                colorRole: "warning"
            },
            lock: {
                glyph: "󰍁",
                label: "Lock session",
                colorRole: "powerLock"
            },
            logout: {
                glyph: "󰍃",
                label: "Log out",
                colorRole: "powerLogout"
            },
            suspend: {
                glyph: "󰤄",
                label: "Suspend",
                colorRole: "powerSuspend"
            },
            hibernate: {
                glyph: "󰜗",
                label: "Hibernate",
                colorRole: "powerHibernate"
            }
        })

    implicitHeight: visibleActions.length ? Math.ceil(visibleActions.length / columns) * 38 - 6 : 0
    height: implicitHeight
    visible: visibleActions.length > 0

    Repeater {
        model: root.visibleActions

        delegate: ActionTile {
            id: powerButton
            required property var modelData
            required property int index
            readonly property var definition: root.definitions[modelData.id]
            readonly property int row: Math.floor(index / root.columns)
            readonly property int rowCount: Math.min(root.columns, root.visibleActions.length - row * root.columns)

            objectName: "powerAction" + modelData.id
            width: 32
            height: 32
            x: Math.max(0, root.width - rowCount * 38 + 6) + (index % root.columns) * 38
            y: row * 38
            themeColors: root.themeColors
            glyph: definition.glyph
            tooltip: modelData.tooltip
            Accessible.name: definition.label
            iconColor: root.themeColors[definition.colorRole]
            hoverColor: {
                const brighter = Qt.lighter(powerButton.iconColor, 1.15);
                // Keep glyph-only focus visible when lightening clips to white.
                return brighter.toString() === powerButton.iconColor.toString() ? Qt.darker(powerButton.iconColor, 1.15) : brighter;
            }
            background: null
            onClicked: root.actionRequested(modelData.id)

            ActionToolTip {
                control: powerButton
                themeColors: root.themeColors
                text: powerButton.tooltip
            }

            contentItem: Text {
                id: powerGlyph

                FontMetrics {
                    id: powerMetrics
                    font: powerGlyph.font
                    readonly property rect ink: tightBoundingRect(powerButton.glyph)
                }

                // Center the painted glyph, not its font advance/line box.
                leftPadding: Math.max(0, (width - powerMetrics.ink.width) / 2 - powerMetrics.ink.x)
                topPadding: Math.max(0, (height - powerMetrics.ink.height) / 2 - powerMetrics.ascent - powerMetrics.ink.y)
                text: powerButton.glyph
                color: !powerButton.enabled ? Qt.darker(powerButton.iconColor, 1.5) : powerButton.down ? Qt.darker(powerButton.iconColor, 1.25) : powerButton.hovered || powerButton.visualFocus ? powerButton.hoverColor : powerButton.iconColor
                font.family: Theme.iconFont
                font.pixelSize: 18
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
                clip: true
            }
        }
    }
}
