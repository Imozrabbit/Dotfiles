import QtQuick

QtObject {
    required property var theme

    // Surfaces and borders.
    readonly property color manager: "#E61C1C22"
    readonly property color tab: "#151519"
    readonly property color card: "#1B1B20"
    readonly property color warningSurface: "#252F3C"
    readonly property color border: "#222229"
    readonly property color selectedBorder: "#5C6B7A"
    readonly property color confirmationBorder: "#1B1B21"
    readonly property color dimOverlay: "#99000000"
    readonly property color guide: "#2B2B32"

    // Text and semantic states.
    readonly property color foreground: "#DCE3EB"
    readonly property color secondary: "#9AA8B8"
    readonly property color dimText: theme.workspaceEmptyColor
    readonly property color accent: "#9EB5C6"
    readonly property color warning: "#B6A1D8"
    readonly property color error: "#C58C91"
    readonly property color success: "#78BEA0"
    readonly property color umu: "#65C7D0"
    readonly property color confirmationText: "#84909E"
    readonly property color cleanupText: "#9685B2"

    // Interaction states and progress.
    readonly property color pressedText: "#7598B5"
    readonly property color hoverText: "#C2D5E5"
    readonly property color button: "#252B34"
    readonly property color buttonPressed: "#1D2633"
    readonly property color buttonHover: "#303947"
    readonly property color cardHover: "#242730"
    readonly property color installedHover: "#202027"
    readonly property color entryHover: "#2E3541"
    readonly property color tabPressed: "#343C47"
    readonly property color tabHover: "#28282E"
    readonly property color tabUnderline: "#7F929F"
    readonly property color removePressed: "#A96F76"
    readonly property color removeHover: "#E3A9AE"
    readonly property color progressTrack: "#303947"
}
