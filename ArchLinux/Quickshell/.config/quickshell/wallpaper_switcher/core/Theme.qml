// This file sets up theme of the application
import QtQuick

QtObject {
    // Font configuration
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int normalText_fontSize: 15
    readonly property int toolTip_fontSize: 14
    readonly property int smallText_fontSize: 13

    // Main colors
    readonly property color bg: "#b30b0e12"
    readonly property color mainColor: "#e6edf3"
    readonly property color subTextColor: "#9aa4b2"

    // Borders
    readonly property color borderColor: "#20ffffff"
    readonly property color hover_borderColor: "#526ea8ff"
    readonly property color onClick_borderColor: "#8cb9ff"

    // Card styling
    readonly property color gridcardColor: "#3010161e"
    readonly property color hover_gridcardColor: "#3a141c26"
    readonly property color gridborderColor: "#12ffffff"
    readonly property color hover_gridborderColor: "#4a6ea8ff"
    readonly property color selected_gridborderColor: "#7a6ea8ff"

    // Accent
    readonly property color accentColor: "#6EA8FF"
    readonly property color accentHover: "#78aeff"
    readonly property color accentPressed: "#4f86d9"

    // Generic surfaces
    readonly property color infillColor: "#18212d"
    readonly property color hover_infillColor: "#223246"
    readonly property color pressed_infillColor: "#141c26"
    readonly property color active_infillColor: "#1d2a39"
    readonly property color inactive_infillColor: "#4f6078a0"

    // Contour
    readonly property color contourColor1: "#B06EA8FF"
    readonly property color contourColor2: "#A85CCFE6"
    readonly property color contourColor3: "#A88F7CFF"
    readonly property int contourMargin: 0
    readonly property int contourWidth: 3
    readonly property int contourRadius: 5

    // Sidebar
    readonly property color sidebarBg: "#ED0E1219"
    readonly property color sidebarSeparator: "#18586678"
    readonly property color menuEntryIcon: "#A7B0BA"

    readonly property color textFieldBg: "#10161e"
    readonly property color hover_textFieldBg: "#141c26"
    readonly property color active_textFieldBg: "#182432"

    readonly property color textFieldBorder: "#2C607286"
    readonly property color hover_textFieldBorder: "#486EA8FF"

    readonly property color selectionColor: "#966EA8FF"
    readonly property color selectedTextColor: mainColor

    // Floating Search Field in main menu
    readonly property color floatingTextFieldBg: "#5010161E"
    readonly property color hover_floatingTextFieldBg: "#70141C26"
    readonly property color active_floatingTextFieldBg: "#90182432"

    readonly property color floatingTextFieldBorder: "#24607286"
    readonly property color hover_floatingTextFieldBorder: "#406EA8FF"

    // Tooltip
    readonly property color tooltipBg: "#e011141a"
    readonly property color tooltipBorder: "#406ea8ff"

    // Radius
    readonly property int radiusSmall: 2
    readonly property int radiusMedium: 6
    readonly property int radiusLarge: 10

    // Spacing
    readonly property int gapSmall: 10
    readonly property int gapMedium: 15
    readonly property int gapLarge: 20
}
