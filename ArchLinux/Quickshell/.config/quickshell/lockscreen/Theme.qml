import QtQuick

QtObject {
    readonly property string fallbackWallpaper: "/home/Zrabbit/Wallpaper/1920x1080/forest.png"
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property string clockFontFamily: "BigBlueTermPlus Nerd Font Mono"
    readonly property string dateFontFamily: "Departure Mono"
    readonly property string proseFontFamily: "Atkinson Hyperlegible Next"
    readonly property string greetFontFamily: "Great Vibes"
    readonly property int fieldFontSize: 13

    readonly property color background: "#101315"
    readonly property color foreground: "#cacccc"
    readonly property color accent: "#cacccc"
    readonly property color urgent: "#a55555"
    readonly property color cardBackground: Qt.rgba(0.09, 0.10, 0.11, 0.68)
    readonly property color cardShadow: Qt.rgba(0, 0, 0, 0.5)
    readonly property color textShadow: Qt.rgba(0, 0, 0, 0.55)
    readonly property color fieldBackground: Qt.rgba(0.063, 0.075, 0.082, 0.8)
    readonly property color placeholder: Qt.rgba(0.792, 0.8, 0.8, 0.66)
    readonly property color selection: Qt.rgba(0.792, 0.8, 0.8, 0.45)
    readonly property color fieldBorder: Qt.rgba(0.792, 0.8, 0.8, 0.1)
    readonly property int fieldWidth: 275
    readonly property int fieldHeight: 35
    readonly property int borderWidth: 1
    readonly property int cornerRadius: 8
    readonly property int cardRadius: 20
    readonly property int headingSize: 16
}
