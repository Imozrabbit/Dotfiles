pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Services.Mpris

Scope {
    id: root

    property bool enabled: false
    property var activePlayers: []
    property var players: []
    readonly property var presentedPlayers: root.enabled ? root.activePlayers.filter((player, index, players) => !!player && root.players.includes(player) && !!player.nativePlayer && players.indexOf(player) === index) : []
    readonly property var progressPlayers: root.presentedPlayers.filter(player => !player.isBrowser && player.nativePlayer.positionSupported && player.duration > 0)
    readonly property bool ticking: root.progressPlayers.some(player => player.playing)

    function isCurrent(player: var): bool {
        return !!player && root.presentedPlayers.includes(player);
    }

    function perform(player: var, action: string): bool {
        if (!root.isCurrent(player))
            return false;
        const native = player.nativePlayer;
        if (action === "previous" && player.canGoPrevious)
            native.previous();
        else if (action === "next" && player.canGoNext)
            native.next();
        else if (action === "playPause" && player.canTogglePlaying)
            native.togglePlaying();
        else if (action === "shuffle" && player.canShuffle)
            native.shuffle = !native.shuffle;
        else if (action === "repeat" && player.canRepeat)
            native.loopState = native.loopState === MprisLoopState.None ? MprisLoopState.Playlist : native.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
        else
            return false;
        return true;
    }

    function seek(player: var, trackKey: var, ratio: var): bool {
        if (!root.isCurrent(player) || player.trackKey !== trackKey || !player.canSeek || typeof ratio !== "number" || !Number.isFinite(ratio))
            return false;
        player.nativePlayer.position = Math.max(0, Math.min(1, ratio)) * player.duration;
        return true;
    }

    function refreshPositions(playingOnly: bool): void {
        for (const player of root.progressPlayers) {
            if (!playingOnly || player.playing)
                player.nativePlayer.positionChanged();
        }
    }

    onProgressPlayersChanged: root.refreshPositions(false)

    Instantiator {
        model: Mpris.players
        delegate: Player {
            required property var modelData
            nativePlayer: modelData
        }
        onObjectAdded: (index, object) => {
            const players = root.players.slice();
            players.splice(index, 0, object);
            root.players = players;
        }
        onObjectRemoved: (index, object) => root.players = root.players.filter(player => player !== object)
    }

    Timer {
        interval: 250
        repeat: true
        running: root.ticking
        onTriggered: root.refreshPositions(true)
    }
}
