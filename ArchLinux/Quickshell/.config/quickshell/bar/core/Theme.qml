import QtQuick

QtObject {
    id: root

    property var backgrounds: ({})

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
    property int fontSizeLarge: 20
    property int fontSizeMedium: 16
    property int fontSizeSmall: 12
    property int radiusMedium: 9

    // -----------------------------------------------------------------------
    // Tooltips
    // -----------------------------------------------------------------------
    property string tooltipFontFamily: "Atkinson Hyperlegible Next"
    property color tooltipBg: root.backgrounds.tooltips ?? "#CC1F1F1F"
    property color tooltipColor: "#D8D8D8"
    property color tooltipBorderColor: "#665A5A5A"
    property int tooltipFontSize: fontSizeMedium - 2

    // -----------------------------------------------------------------------
    // Workspaces
    // -----------------------------------------------------------------------
    // Module
    property color workspaceBg: root.backgrounds.workspaces ?? "#99000000"
    property color workspaceActiveColor: "#f43f5e"
    property color workspaceHoveredColor: "#94e2d5"
    property color workspaceOccupiedColor: whiteColor
    property color workspaceEmptyColor: whiteMutedColor
    property color specialWorkspaceColor: "#7a56c9"
    property int workspaceFontSize: fontSizeMedium

    // -----------------------------------------------------------------------
    // Media
    // -----------------------------------------------------------------------
    property color mediaBg: root.backgrounds.media ?? "#E6252525"

    // -----------------------------------------------------------------------
    // Time and date
    // -----------------------------------------------------------------------
    // Module
    property color timeDateBg: root.backgrounds.timeDate ?? "#211E1C"
    property color timeDateColor: "#B7AA95"
    property color timeDateHoverColor: "#D0B58D"
    property int timeDateFontSize: fontSizeMedium

    // -----------------------------------------------------------------------
    // Calendar
    // -----------------------------------------------------------------------
    // Popup Window
    property color calendarPrimaryColor: "#D5D7DE"
    property color calendarBackgroundColor: root.backgrounds.calendar ?? "#E61F1F1F"
    property color calendarBorderColor: "#405A5A5A"
    property color calendarHeaderColor: "#C2A06A"
    property color calendarWeekdayColor: "#B47C6A"
    property color calendarDayColor: "#D8D8D8"
    property color calendarAdjacentDayColor: "#666666"
    property color weatherSecondaryColor: "#A89B87"
    property color weatherCardBorderColor: "#0CFFFFFF"
    property color calendarTodayColor: "#5A3530"
    property color calendarTodayTextColor: "#E6C7A1"
    property int calendarHeaderFontSize: fontSizeLarge
    property int calendarDayFontSize: fontSizeSmall

    // -----------------------------------------------------------------------
    // Battery panel
    // -----------------------------------------------------------------------
    property color batteryPanelBackgroundColor: root.backgrounds.battery ?? "#E61F1F1F"
    property color batteryPanelBorderColor: calendarBorderColor
    property color batteryPanelHeaderColor: calendarHeaderColor
    property color batteryPanelTextColor: calendarDayColor
    property color batteryPanelMutedColor: calendarAdjacentDayColor
    property color batteryPanelAccentColor: calendarTodayTextColor
    property color batteryPanelActiveButtonColor: calendarTodayColor
    property color batteryPanelInactiveButtonColor: Qt.darker(batteryPanelBackgroundColor, 1.15)
    property color batteryPanelInactiveButtonTextColor: calendarAdjacentDayColor
    property color batteryPanelTrackColor: calendarBorderColor
    property color batteryPanelErrorColor: overloadColor
    property int batteryPanelHeaderFontSize: calendarHeaderFontSize
    property int batteryPanelFontSize: calendarDayFontSize

    // -----------------------------------------------------------------------
    // System usage
    // -----------------------------------------------------------------------
    // Module
    property color cpuUsageBg: root.backgrounds.cpu ?? "#292432"
    property color cpuUsageColor: "#B7A6C9"
    property color gpuUsageBg: root.backgrounds.gpu ?? "#242D2C"
    property color gpuUsageColor: "#A4C1B9"
    property color memUsageBg: root.backgrounds.memory ?? "#222A34"
    property color memUsageColor: "#9EB5C6"
    property color overloadColor: "#FF3B30"
    property int systemUsageFontSize: fontSizeMedium

    // OpenAI subscription usage chip.
    property color openAiUsageBg: root.backgrounds.openAiUsage ?? "#30291F"
    property color openAiUsageColor: calendarHeaderColor

    // -----------------------------------------------------------------------
    // Network usage
    // -----------------------------------------------------------------------
    // Module
    property color networkUsageBg: root.backgrounds.network ?? "#20302F"
    property color wifiPanelBackgroundColor: root.backgrounds.wifi ?? "#991F1F1F"
    property color networkUsageColor: "#B5CBC5"
    property color networkSeparatorColor: "#526A65"
    property int networkUsageFontSize: fontSizeMedium

    // Status accents
    property color networkOnlineColor: "#8FB7AB"
    property color networkOfflineColor: "#B77A72"

    // -----------------------------------------------------------------------
    // Launchers
    // -----------------------------------------------------------------------
    property color launcherColor: workspaceOccupiedColor
    property color launcherHoverColor: workspaceHoveredColor
    property color launcherEmptyColor: whiteMutedColor
    property int launcherFontSize: workspaceFontSize
    property color protonManagerBackgroundColor: root.backgrounds.protonManager ?? "#E61C1C22"

    // -----------------------------------------------------------------------
    // System Tray
    // -----------------------------------------------------------------------
    property color sysTrayBg: "#ED151619"
    property color sysTrayBorderColor: "#335A5550"

    // -----------------------------------------------------------------------
    // Volume
    // -----------------------------------------------------------------------
    property color volumeBg: root.backgrounds.controls ?? "#252733"
    property color volumeColor: "#AAADC8"
    property color volumeMutedColor: "#707072"
    property color volumeHoverColor: "#C4BBD7"
    property color volumeSliderTrackColor: "#45495A"
    property color volumeSliderHandleColor: "#E0E0E1"
    property int volumeFontSize: systemUsageFontSize

    // -----------------------------------------------------------------------
    // Bluetooth
    // -----------------------------------------------------------------------
    property color bluetoothColor: volumeColor
    property color bluetoothConnectedColor: "#94E2D5"
    property color bluetoothMutedColor: volumeMutedColor
    property color bluetoothHoverColor: volumeHoverColor
    property color bluetoothPanelBackgroundColor: root.backgrounds.bluetooth ?? "#E61F1F1F"
    property color bluetoothPanelBorderColor: calendarBorderColor
    property color bluetoothPanelTextColor: calendarDayColor
    property color bluetoothPanelMutedColor: calendarAdjacentDayColor
    property color bluetoothPanelAccentColor: bluetoothConnectedColor
    property color bluetoothPanelCardColor: Qt.darker(bluetoothPanelBackgroundColor, 1.12)
    property color bluetoothPanelButtonColor: Qt.darker(bluetoothPanelBackgroundColor, 1.18)
    property color bluetoothPanelTrackColor: calendarBorderColor
    property color bluetoothPanelErrorColor: overloadColor
    property int bluetoothPanelHeaderFontSize: calendarHeaderFontSize
    property int bluetoothPanelFontSize: calendarDayFontSize

    // -----------------------------------------------------------------------
    // Input method
    // -----------------------------------------------------------------------
    property color inputMethodBg: "#242D2C"
    property color inputMethodColor: "#A4C1B9"
    property color inputMethodHoverColor: "#94E2D5"
    property color inputMethodUnknownColor: whiteMutedColor
    property int inputMethodFontSize: systemUsageFontSize
}
