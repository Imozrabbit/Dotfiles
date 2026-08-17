import QtQuick

// Smoothly reposition cards after filtering changes the grid
Transition {
    NumberAnimation {
        properties: "x,y"

        duration: 160
        easing.type: Easing.OutQuint
    }
}
