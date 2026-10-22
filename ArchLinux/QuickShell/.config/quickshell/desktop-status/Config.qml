import QtQuick

QtObject {
    property string targetScreenName: "HDMI-A-1"
    property int columnWidth: 260
    // Clock date ends at x=10+515-32=493 on the 515 px-wide rotated screen.
    property int rightMargin: 22
    property int topMargin: 110

    property bool quotaEnabled: true
    property bool mouseBatteryEnabled: true
    property bool micBatteryEnabled: true

    property string fontFamily: "BigBlueTermPlus Nerd Font"
    property int fontSize: 20
    property color textColor: "#f2efe1ff"
    property color accentColor: "#cfcfcfff"
    property color mutedColor: "#a7a2ba"
    property color trackColor: "#302b40"

    // Mirror clock/shell.qml; adjust these if the clock's geometry changes.
    property string clockFontFamily: "ttyclock"
    property int clockHourMinuteSize: 120
    property int clockSecondSize: 90
    property int clockTop: 22
    property int clockLeft: 19
    property int clockLineSpacing: 20
    property int clockGap: 20
}
