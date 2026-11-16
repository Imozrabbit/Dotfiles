import QtQuick

QtObject {
    id: root

    property var players: []
    property var screens: []
    property var player: null
    property var screen: null
    property real requestedWidth: 268
    property real cardHeight: 150
    property real x: 0
    property real y: 16
    readonly property real width: Number.isFinite(root.requestedWidth) ? Math.max(0, Math.min(root.requestedWidth, root.screen?.width ?? 0)) : 0
    readonly property real maximumX: Math.max(0, (root.screen?.width ?? 0) - root.width)
    readonly property real maximumY: Math.max(0, (root.screen?.height ?? 0) - root.cardHeight)
    readonly property bool visible: !!root.player && !!root.screen && root.width > 0 && Number.isFinite(root.screen.width) && Number.isFinite(root.screen.height) && Number.isFinite(root.cardHeight) && root.cardHeight > 0 && root.cardHeight <= root.screen.height && root.players.includes(root.player) && root.screens.includes(root.screen)

    function remove(): void {
        root.player = null;
        root.screen = null;
        root.x = 0;
        root.y = 16;
    }

    function removeIfInvalid(): void {
        if (!root.visible)
            root.remove();
    }

    function moveTo(x: real, y: real): void {
        if (!root.visible || !Number.isFinite(x) || !Number.isFinite(y))
            return;
        root.x = Math.max(0, Math.min(root.maximumX, x));
        root.y = Math.max(0, Math.min(root.maximumY, y));
    }

    function toggle(player: var, screen: var): bool {
        if (root.player || root.screen) {
            root.remove();
            return false;
        }
        if (!player || !root.players.includes(player) || !screen || !root.screens.includes(screen) || !Number.isFinite(screen.width) || !Number.isFinite(screen.height) || screen.width <= 0 || screen.height <= 0 || !Number.isFinite(root.requestedWidth) || root.requestedWidth <= 0)
            return false;
        root.screen = screen;
        root.player = player;
        if (!root.visible) {
            root.remove();
            return false;
        }
        root.moveTo((screen.width - root.width) / 2, 16);
        return true;
    }

    onPlayersChanged: if (root.player && !root.players.includes(root.player))
        root.remove()
    onScreensChanged: if (root.screen && !root.screens.includes(root.screen))
        root.remove()
    // Defer state writes until geometry bindings settle; visibility revokes input/actions immediately.
    onVisibleChanged: if (!root.visible)
        Qt.callLater(root.removeIfInvalid)
    onMaximumXChanged: root.moveTo(root.x, root.y)
    onMaximumYChanged: root.moveTo(root.x, root.y)
}
