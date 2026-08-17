import QtQuick

import qs.core as Core

// WiFi colors are local; comments name their former Theme.qml roles.
QtObject {
    required property Core.Theme theme

    readonly property color background: "#1a1b26" // backgroundColor
    readonly property color backgroundAlt: "#20302F" // networkUsageBg
    readonly property color card: "#991F1F1F" // Custom color -> more transparent than the calendarBackgroundColor
    readonly property color foreground: "#D8D8D8" // calendarDayColor
    readonly property color muted: "#666666" // calendarAdjacentDayColor
    readonly property color border: "#405A5A5A" // calendarBorderColor
    readonly property color success: "#8FB7AB" // networkOnlineColor
    readonly property color error: "#B77A72" // networkOfflineColor
    readonly property color accent: "#C2A06A" // calendarHeaderColor
    readonly property int radius: theme.radiusMedium

    readonly property string textFont: theme.tooltipFontFamily
    readonly property string iconFont: theme.fontFamily
}
