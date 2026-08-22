pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

Item {
    id: root

    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property string passwordPamConfig: "quickshell-lock-password"
    readonly property string fingerprintPamConfig: "quickshell-lock-fingerprint"
    readonly property string passwordPamPath: "/etc/pam.d/" + passwordPamConfig
    readonly property string fingerprintPamPath: "/etc/pam.d/" + fingerprintPamConfig
    readonly property bool lockOnStart: Quickshell.env("QUICKSHELL_LOCK_ON_START") === "1"
    readonly property int maxFingerprintCycles: 3
    readonly property int maxFingerprintErrorRetries: 2

    property bool lockRequested: false
    property bool pendingSessionLock: false
    property bool startupLockPending: lockOnStart
    property bool authenticatingPassword: false
    property bool fingerprintAuthenticating: false
    property bool fingerprintPamConfigured: false
    property bool fingerprintEnrolled: false
    property bool fingerprintCycleExhausted: false
    property bool fingerprintDisabled: false
    property bool fingerprintCycleInProgress: false
    property bool suspending: false
    property bool restartFingerprintAfterResume: false
    property int fingerprintCyclesStarted: 0
    property int fingerprintErrorRetries: 0
    property bool passwordPamConfigured: false
    property bool previewVisible: false
    property string enteredPassword: ""
    property string pendingPassword: ""
    property string failureMessage: ""
    property string fingerprintMessage: ""
    property int failedAttempts: 0
    property string lastEvent: "init"
    property string lastEventAt: ""
    property bool strandedLock: false
    property bool strandedLockResolved: false

    readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
    readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
    readonly property bool fingerprintConfigured: fingerprintPamConfigured && fingerprintEnrolled
    readonly property bool fingerprintRetryEnabled: fingerprintConfigured && fingerprintCycleExhausted && !fingerprintDisabled && fingerprintCyclesStarted < maxFingerprintCycles

    Theme {
        id: theme
    }

    WallpaperState {
        id: wallpapers
        fallbackPath: theme.fallbackWallpaper
    }

    function screenName(screen) {
        return screen && screen.name ? screen.name : "";
    }

    function realScreenCount() {
        const screens = Quickshell.screens || [];
        let count = 0;

        for (let i = 0; i < screens.length; i++) {
            const screen = screens[i];
            if (screen && screen.name && screen.width > 0 && screen.height > 0)
                count += 1;
        }

        return count;
    }

    function hasRealScreen() {
        return realScreenCount() > 0;
    }

    function queueSessionLock() {
        pendingSessionLock = true;
        if (!sessionLockStabilizeTimer.running)
            logEvent("lock-pending: screen-stabilizing");
        sessionLockStabilizeTimer.restart();
        if (!pendingSessionLockTimer.running)
            pendingSessionLockTimer.start();
    }

    function requestSessionLock() {
        if (!lockRequested || sessionLock.locked || sessionLock.secure)
            return;
        if (sessionLockStabilizeTimer.running)
            return;
        if (!hasRealScreen()) {
            if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen")
                logEvent("lock-pending: no-real-screen");
            pendingSessionLock = true;
            if (!pendingSessionLockTimer.running)
                pendingSessionLockTimer.start();
            return;
        }

        pendingSessionLock = false;
        pendingSessionLockTimer.stop();
        sessionLock.locked = true;
    }

    function checkStrandedLock() {
        if (strandedLockResolved || strandedLockCheckProc.running)
            return;
        if (locked || lockRequested) {
            strandedLockResolved = true;
            return;
        }
        strandedLockCheckProc.running = true;
    }

    function applyStrandedLockState(raw) {
        let monitors;
        try {
            monitors = JSON.parse(String(raw || ""));
        } catch (error) {
            return false;
        }
        if (!Array.isArray(monitors) || monitors.length === 0)
            return false;

        let hasLock = false;
        let hasReadableMonitor = false;
        for (let i = 0; i < monitors.length; i++) {
            const blockers = Array.isArray(monitors[i].solitaryBlockedBy) ? monitors[i].solitaryBlockedBy : [];
            if (blockers.indexOf("LOCK") >= 0)
                hasLock = true;
            if (blockers.indexOf("WORKSPACE") < 0)
                hasReadableMonitor = true;
        }

        if (!hasLock && !hasReadableMonitor)
            return false;

        strandedLockResolved = true;
        strandedLock = hasLock && !locked && !lockRequested;
        recoverStrandedLock();
        return true;
    }

    function recoverStrandedLock() {
        if (!strandedLock || locked || !passwordPamConfigured)
            return;
        strandedLock = false;
        logEvent("lock-stranded: recovering");
        beginLock();
    }

    function refreshFingerprintStatus() {
        if (!fingerprintPamConfigured) {
            fingerprintEnrolled = false;
            return;
        }
        if (!fingerprintCheckProc.running)
            fingerprintCheckProc.running = true;
    }

    function logEvent(event) {
        lastEvent = event;
        lastEventAt = new Date().toISOString();
        console.log("quickshell lock " + lastEventAt + " " + event);
    }

    function resetAuthenticationState() {
        enteredPassword = "";
        pendingPassword = "";
        failureMessage = "";
        fingerprintMessage = "";
        failedAttempts = 0;
        fingerprintCycleExhausted = false;
        fingerprintDisabled = false;
        fingerprintCycleInProgress = false;
        fingerprintCyclesStarted = 0;
        fingerprintErrorRetries = 0;
        authenticatingPassword = false;
        fingerprintAuthenticating = false;
        fingerprintErrorRetryTimer.stop();
        if (passwordPam.active)
            passwordPam.abort();
        if (fingerprintPam.active)
            fingerprintPam.abort();
    }

    function beginLock() {
        if (!passwordPamConfigured) {
            logEvent("lock-denied: missing-pam");
            return false;
        }

        resetAuthenticationState();
        lockRequested = true;
        logEvent("lock-requested");
        queueSessionLock();
        Qt.callLater(refreshFingerprintStatus);
        return true;
    }

    function finishUnlock() {
        if (!locked && !lockRequested)
            return;
        lockRequested = false;
        pendingSessionLock = false;
        sessionLockStabilizeTimer.stop();
        pendingSessionLockTimer.stop();
        resetAuthenticationState();
        fingerprintResumeTimer.stop();
        suspending = false;
        restartFingerprintAfterResume = false;
        sessionLock.locked = false;
        logEvent("unlocked");
        if (!unlockSessionProc.running)
            unlockSessionProc.running = true;
    }

    function submitPassword(value) {
        const password = String(value || "");
        if (!lockRequested || authenticatingPassword || password.length === 0)
            return;
        pendingPassword = password;
        failureMessage = "";
        authenticatingPassword = true;

        if (!passwordPam.start()) {
            handlePasswordFailure();
            return;
        }
        Qt.callLater(respondToPasswordPrompt);
    }

    function respondToPasswordPrompt() {
        if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired)
            return;
        passwordPam.respond(pendingPassword);
        pendingPassword = "";
    }

    function handlePasswordFailure() {
        if (!lockRequested)
            return;
        authenticatingPassword = false;
        enteredPassword = "";
        pendingPassword = "";
        failedAttempts += 1;
        failureMessage = "Authentication failed (" + failedAttempts + ")";
    }

    function startFingerprint() {
        if (suspending || !lockRequested || !sessionLock.secure || !fingerprintConfigured)
            return;
        if (fingerprintPam.active || fingerprintAuthenticating)
            return;
        if (fingerprintCycleExhausted)
            return;
        if (fingerprintDisabled || fingerprintCyclesStarted >= maxFingerprintCycles) {
            fingerprintDisabled = true;
            fingerprintMessage = "Fingerprint disabled — enter password";
            return;
        }

        fingerprintCyclesStarted += 1;
        fingerprintCycleInProgress = true;
        fingerprintCycleExhausted = false;
        fingerprintMessage = "";
        fingerprintAuthenticating = true;
        if (!fingerprintPam.start()) {
            fingerprintAuthenticating = false;
            fingerprintCycleInProgress = false;
            fingerprintCyclesStarted = Math.max(0, fingerprintCyclesStarted - 1);
            fingerprintCycleExhausted = true;
            fingerprintMessage = "Fingerprint unavailable — tap icon to retry";
        }
    }

    function retryFingerprint() {
        if (fingerprintRetryEnabled) {
            fingerprintErrorRetries = 0;
            fingerprintCycleExhausted = false;
            startFingerprint();
        }
    }

    function updateFingerprintFailure() {
        const remaining = maxFingerprintCycles - fingerprintCyclesStarted;
        if (remaining <= 0) {
            fingerprintDisabled = true;
            fingerprintMessage = "Fingerprint disabled — enter password";
        } else {
            fingerprintMessage = "Fingerprint failed — tap icon to retry (" + remaining + " remaining)";
        }
    }

    function handleFingerprintFinished(result) {
        fingerprintAuthenticating = false;
        const wasInProgress = fingerprintCycleInProgress;
        fingerprintCycleInProgress = false;
        if (!lockRequested)
            return;
        if (suspending)
            return;
        if (result === PamResult.Success) {
            finishUnlock();
            return;
        }
        if (result === PamResult.Error) {
            if (wasInProgress)
                fingerprintCyclesStarted = Math.max(0, fingerprintCyclesStarted - 1);
            if (fingerprintErrorRetries < maxFingerprintErrorRetries) {
                fingerprintErrorRetries += 1;
                fingerprintCycleExhausted = false;
                fingerprintMessage = "";
                fingerprintErrorRetryTimer.restart();
            } else {
                fingerprintCycleExhausted = true;
                fingerprintMessage = "Fingerprint unavailable — tap icon to retry";
            }
            return;
        }
        fingerprintCycleExhausted = true;
        updateFingerprintFailure();
    }

    function prepareSuspend() {
        if (suspending)
            return;
        suspending = true;
        restartFingerprintAfterResume = true;
        fingerprintResumeTimer.stop();
        fingerprintErrorRetryTimer.stop();

        if (passwordPam.active)
            passwordPam.abort();
        authenticatingPassword = false;
        enteredPassword = "";
        pendingPassword = "";

        const interrupted = fingerprintCycleInProgress || fingerprintPam.active;
        if (fingerprintPam.active)
            fingerprintPam.abort();
        fingerprintAuthenticating = false;
        fingerprintCycleInProgress = false;

        if (interrupted) {
            fingerprintCyclesStarted = Math.max(0, fingerprintCyclesStarted - 1);
            fingerprintCycleExhausted = false;
            fingerprintMessage = "";
        }
        logEvent("fingerprint-paused");
    }

    function resumeAfterSuspend() {
        if (!suspending)
            return;
        suspending = false;
        fingerprintErrorRetries = 0;
        logEvent("fingerprint-resume-requested");
        if (restartFingerprintAfterResume && lockRequested && sessionLock.secure)
            fingerprintResumeTimer.restart();
        else if (!lockRequested)
            restartFingerprintAfterResume = false;
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        onSecureStateChanged: {
            root.logEvent("secure=" + secure);
            if (secure) {
                root.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
                if (root.suspending)
                    return;
                if (root.restartFingerprintAfterResume)
                    fingerprintResumeTimer.restart();
                else
                    root.startFingerprint();
            }
        }

        onLockStateChanged: {
            root.logEvent("session-locked=" + locked);
            if (locked) {
                root.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
            }
            if (!locked && root.lockRequested) {
                root.lockRequested = false;
                root.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
                root.resetAuthenticationState();
                fingerprintResumeTimer.stop();
                root.suspending = false;
                root.restartFingerprintAfterResume = false;
            }
        }

        WlSessionLockSurface {
            id: lockSurface
            color: theme.background

            LockView {
                anchors.fill: parent
                theme: theme
                wallpaperPath: wallpapers.pathFor(root.screenName(lockSurface.screen))
                wallpaperVersion: wallpapers.version
                wallpaperFillMode: wallpapers.fillModeFor(root.screenName(lockSurface.screen))
                fingerprintConfigured: root.fingerprintConfigured
                fingerprintAuthenticating: root.fingerprintAuthenticating
                fingerprintRetryEnabled: root.fingerprintRetryEnabled
                fingerprintMessage: root.fingerprintMessage
                authenticatingPassword: root.authenticatingPassword
                failureMessage: root.failureMessage
                inputEnabled: root.lockRequested
                loadBackground: root.locked
                passwordText: root.enteredPassword
                onPasswordTextEdited: function (password) {
                    root.enteredPassword = password;
                }
                onSubmitPassword: function (password) {
                    root.submitPassword(password);
                }
                onClearFailureRequested: root.failureMessage = ""
                onRetryFingerprintRequested: root.retryFingerprint()
            }
        }
    }

    PanelWindow {
        id: previewWindow
        visible: root.previewVisible
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "quickshell-lock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        LockView {
            anchors.fill: parent
            theme: theme
            wallpaperPath: wallpapers.pathFor(root.screenName(previewWindow.screen))
            wallpaperVersion: wallpapers.version
            wallpaperFillMode: wallpapers.fillModeFor(root.screenName(previewWindow.screen))
            fingerprintConfigured: root.fingerprintConfigured
            inputEnabled: false
            loadBackground: root.previewVisible
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.previewVisible = false
        }
    }

    PamContext {
        id: passwordPam
        config: root.passwordPamConfig
        user: root.userName

        onResponseRequiredChanged: root.respondToPasswordPrompt()
        onCompleted: function (result) {
            root.authenticatingPassword = false;
            root.pendingPassword = "";
            if (!root.lockRequested || root.suspending)
                return;
            if (result === PamResult.Success)
                root.finishUnlock();
            else
                root.handlePasswordFailure();
        }
    }

    PamContext {
        id: fingerprintPam
        config: root.fingerprintPamConfig
        user: root.userName
        onCompleted: function (result) {
            root.handleFingerprintFinished(result);
        }
    }

    Process {
        id: fingerprintCheckProc
        command: ["fprintd-list", root.userName]
        stdout: StdioCollector {
            id: fingerprintCheckStdout
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.fingerprintEnrolled = exitCode === 0 && String(fingerprintCheckStdout.text || "").toLowerCase().indexOf("finger") >= 0;
            if (root.lockRequested && sessionLock.secure && root.fingerprintConfigured)
                root.startFingerprint();
            else if (!root.fingerprintConfigured && fingerprintPam.active)
                fingerprintPam.abort();
        }
    }

    Process {
        id: strandedLockCheckProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            id: strandedLockCheckStdout
            waitForEnd: true
        }
        onExited: function (exitCode) {
            if (exitCode === 0)
                root.applyStrandedLockState(strandedLockCheckStdout.text);
        }
    }

    Process {
        id: unlockSessionProc
        command: ["loginctl", "unlock-session"]
    }

    Timer {
        id: fingerprintResumeTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.suspending || !root.lockRequested || !sessionLock.secure)
                return;
            root.restartFingerprintAfterResume = false;
            root.logEvent("fingerprint-resumed");
            root.startFingerprint();
        }
    }

    Timer {
        id: fingerprintErrorRetryTimer
        interval: 1000
        repeat: false
        onTriggered: root.startFingerprint()
    }

    Timer {
        id: sessionLockStabilizeTimer
        interval: 500
        repeat: false
        onTriggered: root.requestSessionLock()
    }

    Timer {
        id: pendingSessionLockTimer
        interval: 100
        repeat: true
        onTriggered: root.requestSessionLock()
    }

    Timer {
        id: strandedLockRetryTimer
        interval: 500
        repeat: true
        readonly property int budget: 20
        property int remaining: budget
        running: !root.strandedLockResolved && remaining > 0

        function rearm() {
            if (!root.strandedLockResolved)
                remaining = budget;
        }

        onTriggered: {
            remaining -= 1;
            root.checkStrandedLock();
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.requestSessionLock();
            strandedLockRetryTimer.rearm();
            root.checkStrandedLock();
        }
    }

    FileView {
        path: root.passwordPamPath
        watchChanges: true
        printErrors: false
        onLoaded: root.passwordPamConfigured = true
        onLoadFailed: root.passwordPamConfigured = false
        onFileChanged: reload()
    }

    FileView {
        path: root.fingerprintPamPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.fingerprintPamConfigured = true;
            root.refreshFingerprintStatus();
        }
        onLoadFailed: {
            root.fingerprintPamConfigured = false;
            root.fingerprintEnrolled = false;
        }
        onFileChanged: reload()
    }

    onPasswordPamConfiguredChanged: {
        if (!passwordPamConfigured)
            return;
        strandedLock = false;
        strandedLockResolved = false;
        strandedLockRetryTimer.rearm();
        checkStrandedLock();
        if (startupLockPending) {
            startupLockPending = false;
            beginLock();
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): string {
            if (!root.passwordPamConfigured)
                return "missing-pam";
            if (!root.locked && !root.beginLock())
                return "failed";
            return "ok";
        }

        function isLocked(): string {
            return root.locked ? "true" : "false";
        }

        function status(): string {
            return JSON.stringify({
                locked: root.locked,
                requested: root.lockRequested,
                pending: root.pendingSessionLock,
                sessionLocked: sessionLock.locked,
                secure: sessionLock.secure,
                realScreens: root.realScreenCount(),
                passwordPam: root.passwordPamConfigured,
                fingerprint: root.fingerprintConfigured,
                fingerprintCycles: root.fingerprintCyclesStarted,
                fingerprintDisabled: root.fingerprintDisabled,
                suspending: root.suspending,
                authenticating: root.authenticating,
                lastEvent: root.lastEvent,
                lastEventAt: root.lastEventAt
            });
        }

        function preview(): string {
            root.refreshFingerprintStatus();
            root.previewVisible = true;
            return "ok";
        }

        function hidePreview(): string {
            root.previewVisible = false;
            return "ok";
        }

        function prepareSuspend(): string {
            root.prepareSuspend();
            return "ok";
        }

        function resumeAfterSuspend(): string {
            root.resumeAfterSuspend();
            return "ok";
        }
    }
}
