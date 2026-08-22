import QtQuick

QtObject {
    readonly property string fallbackWallpaper: "/home/Zrabbit/Wallpaper/1920x1080/forest.png"
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"

    readonly property color background: "#101315"
    readonly property color foreground: "#cacccc"
    readonly property color accent: "#cacccc"
    readonly property color urgent: "#a55555"
    readonly property color fieldBackground: Qt.rgba(0.063, 0.075, 0.082, 0.8)
    readonly property color placeholder: Qt.rgba(0.792, 0.8, 0.8, 0.66)
    readonly property color selection: Qt.rgba(0.792, 0.8, 0.8, 0.45)
    readonly property color fieldBorder: Qt.rgba(0.792, 0.8, 0.8, 0.45)
    readonly property color statusBackground: Qt.rgba(0.063, 0.075, 0.082, 0.92)
    readonly property color statusBorder: Qt.rgba(0.647, 0.333, 0.333, 0.75)

    readonly property int fieldWidth: 320
    readonly property int fieldHeight: 50
    readonly property int borderWidth: 1
    readonly property int cornerRadius: 9
    readonly property int headingSize: 16
}
