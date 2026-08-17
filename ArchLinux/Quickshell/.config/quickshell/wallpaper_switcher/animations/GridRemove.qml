import QtQuick

// Fade and slightly shrink a card before removing it
Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "opacity"
            to: 0

            duration: 100
            easing.type: Easing.InQuint
        }

        NumberAnimation {
            property: "scale"
            to: 0

            duration: 100
            easing.type: Easing.InQuint
        }
    }
}
