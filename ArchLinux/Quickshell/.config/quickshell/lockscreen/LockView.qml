pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property Theme theme
    property string wallpaperPath: ""
    property int wallpaperVersion: 0
    property int wallpaperFillMode: Image.PreserveAspectFit
    property bool fingerprintConfigured: false
    property bool fingerprintAuthenticating: false
    property bool fingerprintRetryEnabled: false
    property string fingerprintMessage: ""
    property bool authenticatingPassword: false
    property string failureMessage: ""
    property bool inputEnabled: true
    property bool loadBackground: true
    property string passwordText: ""
    property bool syncingPasswordText: false
    property date currentTime: new Date()

    readonly property string placeholderText: "Enter Password"
    readonly property int fieldFontSize: theme.fieldFontSize
    readonly property int passwordDotFontSize: Math.round(theme.headingSize * 1)
    readonly property int passwordDotLetterSpacing: Math.round(theme.headingSize * 0.19)
    readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
    readonly property real passwordDotScale: dotMetrics.advanceWidth > 0 ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth) : 1
    readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
    readonly property bool errorState: failureMessage.length > 0
    readonly property string statusMessage: failureMessage.length > 0 ? failureMessage : fingerprintMessage
    readonly property string greetingText: greetingForHour(currentTime.getHours())
    readonly property string authenticationPrompt: {
        if (authenticatingPassword)
            return "Verifying password...";
        if (fingerprintAuthenticating)
            return "Scanning fingerprint...";
        if (fingerprintConfigured && fingerprintMessage.length === 0)
            return "Touch fingerprint sensor or enter your password";
        return "Enter your password";
    }

    signal submitPassword(string password)
    signal passwordTextEdited(string password)
    signal clearFailureRequested
    signal retryFingerprintRequested

    function fileUrl(path) {
        if (!path)
            return "";
        const encoded = String(path).split("/").map(encodeURIComponent).join("/");
        return "file://" + encoded + "?v=" + wallpaperVersion;
    }

    function forcePasswordFocus() {
        passwordInput.forceActiveFocus();
    }

    function greetingForHour(hour) {
        if (hour < 6)
            return "TF you doing at this time";
        if (hour < 12)
            return "Good morning";
        if (hour < 18)
            return "Good afternoon";
        return "Good evening";
    }

    function updateClock() {
        const now = new Date();
        currentTime = now;
        clockTimer.interval = Math.max(1000, 60000 - now.getSeconds() * 1000 - now.getMilliseconds());
        clockTimer.restart();
    }

    function syncPasswordText() {
        if (passwordInput.text === passwordText)
            return;
        syncingPasswordText = true;
        passwordInput.text = passwordText;
        syncingPasswordText = false;
    }

    onPasswordTextChanged: syncPasswordText()
    onInputEnabledChanged: {
        if (inputEnabled)
            Qt.callLater(forcePasswordFocus);
    }
    Component.onCompleted: {
        syncPasswordText();
        updateClock();
        if (inputEnabled)
            Qt.callLater(forcePasswordFocus);
    }

    TextMetrics {
        id: dotMetrics
        font.family: root.theme.fontFamily
        font.pixelSize: root.passwordDotFontSize
        font.letterSpacing: root.passwordDotLetterSpacing
        text: "●".repeat(passwordInput.text.length)
    }

    Timer {
        id: clockTimer
        repeat: false
        onTriggered: root.updateClock()
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.background

        Image {
            id: wallpaper
            anchors.fill: parent
            source: root.loadBackground ? root.fileUrl(root.wallpaperPath) : ""
            fillMode: root.wallpaperFillMode
            asynchronous: true
            cache: false
            sourceSize.width: width
            sourceSize.height: height
        }

        MultiEffect {
            anchors.fill: wallpaper
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
            blur: 0.5
            blurMax: 40
            blurMultiplier: 1
            brightness: -0.05
            contrast: -0.04
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.ArrowCursor
            onClicked: root.forcePasswordFocus()
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: card.top
            anchors.bottomMargin: 25
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.currentTime, "HH:mm")
                color: root.theme.foreground
                font.family: root.theme.clockFontFamily
                font.pixelSize: Math.round(root.theme.headingSize * 6)
                font.weight: Font.DemiBold
                font.letterSpacing: -2
                horizontalAlignment: Text.AlignHCenter
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.theme.textShadow
                    shadowBlur: 0.8
                    shadowVerticalOffset: 2
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(root.currentTime, "dddd, d MMMM")
                color: root.theme.placeholder
                font.family: root.theme.dateFontFamily
                font.pixelSize: Math.round(root.theme.headingSize * 1.4)
                font.letterSpacing: 1
                horizontalAlignment: Text.AlignHCenter
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.theme.textShadow
                    shadowBlur: 0.8
                    shadowVerticalOffset: 1
                }
            }
        }

        Rectangle {
            id: card
            width: root.theme.fieldWidth + 120
            height: cardContent.implicitHeight + 80
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: height / 2 - 28 - greetingLabel.height / 2
            radius: root.theme.cardRadius
            color: root.theme.cardBackground
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.theme.cardShadow
                shadowBlur: 1
                shadowVerticalOffset: 12
            }

            Column {
                id: cardContent
                anchors.centerIn: parent
                width: root.theme.fieldWidth
                spacing: 0

                Text {
                    id: greetingLabel
                    width: parent.width
                    text: root.greetingText
                    color: root.theme.foreground
                    font.family: root.theme.greetFontFamily
                    font.pixelSize: Math.round(root.theme.headingSize * 3.2)
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    width: 1
                    height: 14
                }

                Text {
                    width: parent.width
                    text: root.authenticationPrompt
                    transform: Translate {
                        y: 5
                    }
                    color: root.theme.placeholder
                    font.family: root.theme.proseFontFamily
                    font.pixelSize: Math.max(12, root.theme.headingSize - 3)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Item {
                    width: 1
                    height: 6
                }

                Rectangle {
                    id: inputField
                    width: parent.width
                    height: root.theme.fieldHeight
                    transform: Translate {
                        y: 10
                    }
                    color: root.theme.fieldBackground
                    radius: root.theme.cornerRadius
                    border.width: root.theme.borderWidth
                    border.color: root.errorState ? root.theme.urgent : root.theme.fieldBorder

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: root.theme.borderWidth
                        anchors.rightMargin: root.theme.borderWidth + 18 + root.fingerprintReserve
                        anchors.leftMargin: root.theme.borderWidth + 18 + root.fingerprintReserve
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        activeFocusOnPress: true
                        clip: true
                        enabled: root.inputEnabled && !root.authenticatingPassword
                        readOnly: root.authenticatingPassword
                        echoMode: TextInput.Password
                        passwordCharacter: "\u25CF"
                        passwordMaskDelay: 0
                        maximumLength: 512
                        color: root.theme.foreground
                        selectionColor: root.theme.selection
                        selectedTextColor: root.theme.foreground
                        font.family: root.theme.fontFamily
                        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
                        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
                        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
                        cursorDelegate: Rectangle {
                            width: 2
                            color: root.theme.foreground
                            visible: passwordInput.cursorVisible
                        }

                        onTextChanged: {
                            if (!root.syncingPasswordText)
                                root.passwordTextEdited(text);
                            if (text.length > 0 && root.failureMessage.length > 0)
                                root.clearFailureRequested();
                        }

                        onAccepted: {
                            const submitted = root.passwordText;
                            root.passwordTextEdited("");
                            if (submitted.length > 0)
                                root.submitPassword(submitted);
                            else if (root.fingerprintRetryEnabled)
                                root.retryFingerprintRequested();
                        }

                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                                root.passwordTextEdited("");
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        anchors.fill: passwordInput
                        text: root.authenticatingPassword ? "" : root.placeholderText
                        visible: passwordInput.text.length === 0
                        color: root.theme.placeholder
                        font.family: root.theme.proseFontFamily
                        font.pixelSize: root.fieldFontSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        id: fingerprintIcon
                        objectName: "fingerprintIndicator"
                        anchors.right: parent.right
                        anchors.rightMargin: root.theme.borderWidth + 18
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.fingerprintConfigured
                        text: "󰈷"
                        color: root.fingerprintMessage.length > 0 ? root.theme.urgent : (root.fingerprintAuthenticating ? root.theme.accent : root.theme.placeholder)
                        font.family: root.theme.fontFamily
                        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter

                        MouseArea {
                            width: 44
                            height: 44
                            anchors.centerIn: parent
                            enabled: root.fingerprintRetryEnabled
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.retryFingerprintRequested()
                        }
                    }
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 15
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 32, 560)
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            color: root.theme.urgent
            font.family: root.theme.proseFontFamily
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            style: Text.Outline
            styleColor: root.theme.background
        }
    }
}
