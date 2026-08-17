import QtQuick

// Fade and slightly enlarge a card when it appears
Transition {
    ParallelAnimation {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1

            duration: 200
            easing.type: Easing.OutQuint
        }

        NumberAnimation {
            property: "scale"
            from: 0.4
            to: 1

            duration: 210
            easing.type: Easing.OutBack
        }
    }
}
