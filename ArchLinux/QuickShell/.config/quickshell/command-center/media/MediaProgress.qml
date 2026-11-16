import QtQuick
import QtQuick.Window
import "../common/Theme.js" as Theme

Canvas {
    id: root

    property var progress: 0
    property color waveColor: Theme.colors.tileActive
    property color trackColor: Theme.colors.sliderTrack
    property bool playing: false
    property real phase: 0
    property bool seekable: false
    property var seekPlayer: null
    property var trackKey: null
    property bool seeking: false
    property bool pointerFocused: false
    property real previewProgress: 0
    signal seekRequested(real ratio)
    readonly property real boundedProgress: seeking ? previewProgress : typeof progress === "number" && Number.isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0
    readonly property real filledWidth: Math.max(0, width) * boundedProgress
    readonly property bool split: boundedProgress > 0 && boundedProgress < 1
    readonly property real playedEndX: split ? Math.max(0, filledWidth - 5) : filledWidth
    readonly property real remainingStartX: split ? Math.min(Math.max(0, width), filledWidth + 5) : filledWidth

    implicitHeight: 26
    enabled: seekable
    activeFocusOnTab: true
    Accessible.role: seekable ? Accessible.Slider : Accessible.ProgressBar
    Accessible.name: "Playback position"
    Accessible.description: Math.round(boundedProgress * 100) + "%" + (seekable ? "; Left/Right seeks5%, Home/End seeks start/end" : "; seeking unavailable")
    Accessible.onIncreaseAction: root.requestSeek(root.boundedProgress + 0.05)
    Accessible.onDecreaseAction: root.requestSeek(root.boundedProgress - 0.05)

    function cancelSeek(): void {
        root.seeking = false;
    }

    function requestSeek(ratio: real): void {
        if (root.seekable && root.enabled && root.visible && root.width > 0 && root.Window.window?.visible === true) {
            root.cancelSeek();
            root.seekRequested(Math.max(0, Math.min(1, ratio)));
        }
    }

    Keys.onPressed: event => {
        root.pointerFocused = false;
        if (event.key === Qt.Key_Escape && root.seeking) {
            root.cancelSeek();
            event.accepted = true;
        } else if (root.seekable && !(event.modifiers & Qt.ControlModifier)) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                root.requestSeek(root.boundedProgress + (event.key === Qt.Key_Right ? 0.05 : -0.05));
                event.accepted = true;
            } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                root.requestSeek(event.key === Qt.Key_Home ? 0 : 1);
                event.accepted = true;
            }
        }
    }

    onSeekPlayerChanged: root.cancelSeek()
    onTrackKeyChanged: root.cancelSeek()
    onSeekableChanged: if (!seekable)
        root.cancelSeek()
    onEnabledChanged: if (!enabled)
        root.cancelSeek()
    onActiveFocusChanged: if (!activeFocus)
        root.pointerFocused = false
    onVisibleChanged: {
        if (visible)
            requestPaint();
        else
            root.cancelSeek();
    }
    Connections {
        target: root.Window.window
        function onVisibleChanged() {
            if (!root.Window.window.visible)
                root.cancelSeek();
        }
        function onWidthChanged() {
            root.cancelSeek();
        }
        function onHeightChanged() {
            root.cancelSeek();
        }
    }

    onPlayedEndXChanged: requestPaint()
    onPhaseChanged: requestPaint()
    onWaveColorChanged: requestPaint()
    onWidthChanged: {
        root.cancelSeek();
        requestPaint();
    }
    onHeightChanged: {
        root.cancelSeek();
        requestPaint();
    }
    onAvailableChanged: if (available)
        requestPaint()

    MouseArea {
        anchors.fill: parent
        enabled: root.seekable && root.width > 0
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.pointerFocused = true;
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.previewProgress = Math.max(0, Math.min(1, mouse.x / root.width));
            root.seeking = true;
        }
        onPositionChanged: mouse => {
            if (root.seeking)
                root.previewProgress = Math.max(0, Math.min(1, mouse.x / root.width));
        }
        onReleased: mouse => {
            if (root.seeking)
                root.requestSeek(mouse.x / root.width);
        }
        onCanceled: root.cancelSeek()
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: 3
        border.width: 1
        border.color: root.waveColor
        visible: root.activeFocus && root.seekable && !root.pointerFocused
    }

    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 1200
        loops: Animation.Infinite
        running: root.playing && root.visible && root.Window.window?.visible === true
    }

    Rectangle {
        objectName: "mediaRemainingTrack"
        x: root.remainingStartX
        width: Math.max(0, root.width - x)
        y: (root.height - height) / 2
        height: 6
        radius: 3
        color: root.trackColor
        visible: width > 0
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const trackH = 6;
        const radius = 3;
        const centerY = height / 2;
        const w = root.playedEndX;
        if (w <= 0)
            return;
        if (w < radius * 2) {
            ctx.beginPath();
            ctx.arc(w / 2, centerY, w / 2, 0, Math.PI * 2);
            ctx.fillStyle = root.waveColor;
            ctx.fill();
            return;
        }
        const endCenterX = w - radius;
        ctx.beginPath();
        ctx.moveTo(endCenterX, centerY + trackH / 2);
        ctx.lineTo(radius, centerY + trackH / 2);
        ctx.arc(radius, centerY, radius, Math.PI / 2, Math.PI * 1.5);
        const freq = 0.05;
        const maxAmp = 6;
        const fadeLen = 30;
        for (let x = radius; x <= endCenterX; ++x) {
            const leftDist = x - radius;
            const rightDist = endCenterX - x;
            let envelope = 1;
            if (leftDist < fadeLen)
                envelope = Math.sin((leftDist / fadeLen) * (Math.PI / 2));
            if (rightDist < fadeLen) {
                const envRight = Math.sin((rightDist / fadeLen) * (Math.PI / 2));
                if (envRight < envelope)
                    envelope = envRight;
            }
            const wave1 = Math.sin(x * freq - root.phase);
            const wave2 = Math.sin(x * freq * 1.5 - root.phase * 2) * 0.3;
            const combined = Math.max(0, Math.min(1, (wave1 + wave2 + 1.3) / (2 * 1.3)));
            ctx.lineTo(x, (centerY - trackH / 2) - combined * maxAmp * envelope);
        }
        ctx.arc(endCenterX, centerY, radius, -Math.PI / 2, Math.PI / 2);
        ctx.closePath();
        ctx.fillStyle = root.waveColor;
        ctx.fill();
    }
}
