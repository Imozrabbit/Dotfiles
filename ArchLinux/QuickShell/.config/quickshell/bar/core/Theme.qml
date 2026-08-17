import QtQuick

QtObject {
    // -----------------------------------------------------------------------
    // General colors
    // -----------------------------------------------------------------------
    property color backgroundColor: "#1a1b26"
    property color whiteColor: "#e0e0e1"
    property color whiteMutedColor: "#707072"
    property color whiteMutatedColor: "#A1BDCE"

    // -----------------------------------------------------------------------
    // General typography
    // -----------------------------------------------------------------------
    property string fontFamily: "JetBrainsMono Nerd Font Propo"
    property string tooltipFontFamily: "Atkinson Hyperlegible Next"
    property int fontSizeLarge: 20
    property int fontSizeMedium: 16
    property int fontSizeSmall: 12
    property int radiusMedium: 9

    // -----------------------------------------------------------------------
    // Workspaces
    // -----------------------------------------------------------------------
    // Module
    property color workspaceBg: "#05F5F5FA"
    property color workspaceActiveColor: "#f43f5e"
    property color workspaceHoveredColor: "#94e2d5"
    property color workspaceOccupiedColor: whiteColor
    property color workspaceEmptyColor: whiteMutedColor
    property color specialWorkspaceColor: "#7a56c9"
    property int workspaceFontSize: fontSizeMedium

    // -----------------------------------------------------------------------
    // Time and date
    // -----------------------------------------------------------------------
    // Module
    property color timeDateBg: "#211E1C"
    property color timeDateColor: "#B7AA95"
    property color timeDateHoverColor: "#D0B58D"
    property int timeDateFontSize: fontSizeMedium

    // -----------------------------------------------------------------------
    // Calendar
    // -----------------------------------------------------------------------
    // Popup Window
    property color calendarPrimaryColor: "#D5D7DE"
    property color calendarBackgroundColor: "#E61F1F1F"
    property color calendarBorderColor: "#405A5A5A"
    property color calendarHeaderColor: "#C2A06A"
    property color calendarWeekdayColor: "#B47C6A"
    property color calendarDayColor: "#D8D8D8"
    property color calendarAdjacentDayColor: "#666666"
    property color calendarTodayColor: "#5A3530"
    property color calendarTodayTextColor: "#E6C7A1"
    property int calendarHeaderFontSize: fontSizeLarge
    property int calendarDayFontSize: fontSizeSmall

    // -----------------------------------------------------------------------
    // System usage
    // -----------------------------------------------------------------------
    // Module
    property color cpuUsageBg: "#292432"
    property color cpuUsageColor: "#B7A6C9"
    property color memUsageBg: "#222A34"
    property color memUsageColor: "#9EB5C6"
    property color overloadColor: "#FF3B30"
    property int systemUsageFontSize: fontSizeMedium

    // -----------------------------------------------------------------------
    // Network usage
    // -----------------------------------------------------------------------
    // Module
    property color networkUsageBg: "#20302F"
    property color networkUsageColor: "#B5CBC5"
    property color networkSeparatorColor: "#526A65"
    property int networkUsageFontSize: fontSizeMedium

    // Network tooltip
    property color networkTooltipBg: "#CC1F1F1F"
    property color networkTooltipColor: "#D8D8D8"
    property color networkTooltipBorderColor: "#665A5A5A"
    property int networkTooltipFontSize: fontSizeMedium - 2

    // Status accents
    property color networkOnlineColor: "#8FB7AB"
    property color networkOfflineColor: "#B77A72"

    // WiFi selector
    property color wifiSelectorBg: calendarBackgroundColor
    property color wifiSelectorBorderColor: calendarBorderColor
    property color wifiSelectorHeaderColor: calendarHeaderColor
    property color wifiSelectorTextColor: calendarDayColor
    property color wifiSelectorMutedColor: calendarAdjacentDayColor
    property color wifiSelectorHoverBg: calendarTodayColor
    property color wifiSelectorActiveColor: calendarTodayTextColor
    property color wifiSelectorWarningColor: calendarWeekdayColor
    property string wifiSelectorFontFamily: fontFamily
    property int wifiSelectorHeaderFontSize: calendarHeaderFontSize
    property int wifiSelectorBodyFontSize: calendarDayFontSize

    // -----------------------------------------------------------------------
    // Launchers
    // -----------------------------------------------------------------------
    property color launcherColor: workspaceOccupiedColor
    property color launcherHoverColor: workspaceHoveredColor
    property color launcherEmptyColor: whiteMutedColor
    property int launcherFontSize: workspaceFontSize

    // -----------------------------------------------------------------------
    // Volume
    // -----------------------------------------------------------------------
    property color volumeBg: "#252733"
    property color volumeColor: "#AAADC8"
    property color volumeMutedColor: "#707072"
    property color volumeHoverColor: "#C4BBD7"
    property color volumeSliderTrackColor: "#45495A"
    property color volumeSliderHandleColor: "#E0E0E1"
    property int volumeFontSize: systemUsageFontSize

    // -----------------------------------------------------------------------
    // Input method
    // -----------------------------------------------------------------------
    property color inputMethodBg: "#242D2C"
    property color inputMethodColor: "#A4C1B9"
    property color inputMethodHoverColor: "#94E2D5"
    property color inputMethodUnknownColor: whiteMutedColor
    property int inputMethodFontSize: systemUsageFontSize
}
