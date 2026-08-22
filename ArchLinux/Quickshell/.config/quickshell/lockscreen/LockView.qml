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

    readonly property string placeholderText: "Enter Password"
    readonly property int fieldFontSize: Math.round(theme.headingSize)
    readonly property int passwordDotFontSize: Math.round(theme.headingSize * 1.125)
    readonly property int passwordDotLetterSpacing: Math.round(theme.headingSize * 0.19)
    readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
    readonly property real passwordDotScale: dotMetrics.advanceWidth > 0 ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth) : 1
    readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
    readonly property bool errorState: failureMessage.length > 0
    readonly property string statusMessage: failureMessage.length > 0 ? failureMessage : fingerprintMessage

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
            blur: 0.6
            blurMax: 64
            blurMultiplier: 1.1
            contrast: -0.08
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.ArrowCursor
            onClicked: root.forcePasswordFocus()
        }

        Rectangle {
            id: inputField
            width: root.theme.fieldWidth
            height: root.theme.fieldHeight
            anchors.centerIn: parent
            color: root.theme.fieldBackground
            radius: root.theme.cornerRadius
            border.width: root.theme.borderWidth
            border.color: root.errorState ? root.theme.urgent : root.theme.fieldBorder
            clip: true

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
                text: root.authenticatingPassword ? "Checking…" : root.placeholderText
                visible: passwordInput.text.length === 0
                color: root.authenticatingPassword ? root.theme.foreground : root.theme.placeholder
                font.family: root.theme.fontFamily
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

        Rectangle {
            id: statusArea
            anchors.top: inputField.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: inputField.horizontalCenter
            width: Math.min(parent.width - 32, Math.min(480, Math.max(inputField.width, statusText.implicitWidth + 28)))
            height: Math.max(34, statusText.implicitHeight + 14)
            visible: root.statusMessage.length > 0
            color: root.theme.statusBackground
            radius: root.theme.cornerRadius
            border.width: 1
            border.color: root.theme.statusBorder

            Text {
                id: statusText
                anchors.fill: parent
                anchors.margins: 7
                text: root.statusMessage
                color: root.theme.foreground
                font.family: root.theme.fontFamily
                font.pixelSize: Math.max(12, root.fieldFontSize - 3)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
