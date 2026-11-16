pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../common/Theme.js" as Theme

Item {
    id: root

    property var players: []
    property var sourceNames: ({})
    property var spectrumLevels: []
    property var themeColors: Theme.colors
    property bool active: true
    property bool desktopCopyActive: false
    property var displayedPlayers: [null]
    property alias currentIndex: view.currentIndex
    readonly property var currentPlayer: displayedPlayers[currentIndex] || null
    // SwipeView can omit its initial currentItemChanged while Repeater fills it.
    readonly property var currentCard: view.count ? view.itemAt(root.currentIndex) : null
    signal actionRequested(var player, string action)
    signal seekRequested(var player, var trackKey, real ratio)

    implicitHeight: view.count ? view.height + (view.count > 1 ? 10 : 0) : 0
    height: implicitHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: "Media sources"
    Accessible.description: players.length ? "Source " + (currentIndex + 1) + " of " + players.length + "; Ctrl+Left/Right changes source" : "No media players"

    function synchronizePlayers(): void {
        const selected = root.currentPlayer;
        const previousIndex = view.currentIndex;
        root.displayedPlayers = root.players.length ? root.players.slice() : [null];
        const selectedIndex = root.players.indexOf(selected);
        view.currentIndex = selectedIndex >= 0 ? selectedIndex : Math.max(0, Math.min(previousIndex, root.displayedPlayers.length - 1));
    }

    onPlayersChanged: root.synchronizePlayers()

    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + (event.key === Qt.Key_Right ? 1 : -1)));
            event.accepted = true;
        }
    }

    SwipeView {
        id: view
        objectName: "mediaSwipeView"
        width: root.width
        topPadding: root.currentCard?.sourceOverhang ?? 0
        height: root.currentCard ? root.currentCard.implicitHeight + topPadding : 0
        interactive: count > 1 && !root.currentCard?.seeking
        clip: true

        Repeater {
            model: root.displayedPlayers
            delegate: MediaCard {
                required property var modelData
                required property int index
                objectName: index === 0 ? "mediaCard" : "mediaCard" + index
                player: modelData
                sourceNames: root.sourceNames
                themeColors: root.themeColors
                spectrumLevels: active && root.visible ? root.spectrumLevels : []
                active: root.active && SwipeView.isCurrentItem
                desktopCopyActive: root.desktopCopyActive
                enabled: active
                onPreviousRequested: root.actionRequested(player, "previous")
                onPlaybackToggleRequested: root.actionRequested(player, "playPause")
                onNextRequested: root.actionRequested(player, "next")
                onShuffleRequested: root.actionRequested(player, "shuffle")
                onRepeatRequested: root.actionRequested(player, "repeat")
                onDesktopRequested: root.actionRequested(player, "toDesktop")
                onSeekRequested: (trackKey, ratio) => root.seekRequested(player, trackKey, ratio)
            }
        }
    }

    Row {
        id: indicator
        objectName: "mediaPageIndicator"
        anchors.horizontalCenter: parent.horizontalCenter
        y: view.height + 4
        height: 3
        spacing: 4
        readonly property int count: view.count
        readonly property int currentIndex: view.currentIndex
        visible: count > 1
        Repeater {
            model: indicator.count
            delegate: Rectangle {
                required property int index
                width: 3
                height: 3
                radius: 1.5
                color: root.themeColors.text
                opacity: index === indicator.currentIndex ? 0.4 : 0.15
            }
        }
    }
}
