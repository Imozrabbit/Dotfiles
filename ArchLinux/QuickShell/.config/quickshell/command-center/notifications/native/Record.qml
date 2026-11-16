pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Policy.js" as Policy

Scope {
    id: root
    property var notification: null
    property string key: ""
    property var data: ({})
    property string signature: ""
    property var revision: 1
    property var archiveId: 0
    property var receivedAt: 0
    property var updatedAt: 0
    property string thumbnail: ""
    property string captureToken: ""
    property bool shown: false
    property bool dndSuppressed: false
    property bool hovered: false
    property bool focused: false
    property bool closing: false
    property string screenName: ""
    property bool initialized: false
    signal updated(var record)
    signal closed(var record)
    signal expired(var record)

    function observe(): bool {
        if (!root.initialized || root.closing || !root.notification?.tracked)
            return false;
        const data = Policy.snapshot(root.notification);
        const signature = JSON.stringify(data);
        if (signature === root.signature)
            return false;
        root.signature = signature;
        root.data = data;
        root.revision++;
        root.updatedAt = Math.max(Date.now(), root.updatedAt + 1);
        root.updated(root);
        return true;
    }

    function restart(): void {
        if (!root.initialized)
            return;
        countdown.stop();
        if (root.shown && root.screenName !== "" && !root.hovered && !root.focused && countdown.interval > 0)
            countdown.start();
    }

    onShownChanged: root.restart()
    onHoveredChanged: root.restart()
    onFocusedChanged: root.restart()
    onScreenNameChanged: root.restart()
    Component.onCompleted: {
        root.initialized = true;
        root.restart();
    }

    Timer {
        id: countdown
        interval: Policy.duration(root.data.urgency, root.data.timeout)
        onTriggered: root.expired(root)
    }

    Connections {
        target: root.notification
        function onClosed() {
            root.closed(root);
        }
        function onAppNameChanged() {
            Qt.callLater(root.observe);
        }
        function onAppIconChanged() {
            Qt.callLater(root.observe);
        }
        function onSummaryChanged() {
            Qt.callLater(root.observe);
        }
        function onBodyChanged() {
            Qt.callLater(root.observe);
        }
        function onImageChanged() {
            Qt.callLater(root.observe);
        }
        function onHintsChanged() {
            Qt.callLater(root.observe);
        }
        function onUrgencyChanged() {
            Qt.callLater(root.observe);
        }
        function onExpireTimeoutChanged() {
            Qt.callLater(root.observe);
        }
        function onTransientChanged() {
            Qt.callLater(root.observe);
        }
        function onResidentChanged() {
            Qt.callLater(root.observe);
        }
        function onActionsChanged() {
            Qt.callLater(root.observe);
        }
        function onHasInlineReplyChanged() {
            Qt.callLater(root.observe);
        }
        function onInlineReplyPlaceholderChanged() {
            Qt.callLater(root.observe);
        }
    }
}
