import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: root

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        const states = players.map(candidate => candidate.playbackState);
        let index = states.indexOf(MprisPlaybackState.Playing);
        if (index < 0)
            index = states.indexOf(MprisPlaybackState.Paused);
        return index >= 0 ? players[index] : null;
    }

    readonly property int playbackState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool active: root.player !== null
    readonly property bool playing: root.playbackState === MprisPlaybackState.Playing
    readonly property bool paused: root.playbackState === MprisPlaybackState.Paused

    readonly property bool canPause: root.player ? root.player.canPause : false
    readonly property bool canControl: root.player ? root.player.canControl : false
    readonly property bool canTogglePlaying: root.player ? root.player.canTogglePlaying : false

    readonly property string app: root.player ? root.player.identity : ""
    readonly property string title: root.player ? root.player.trackTitle : ""
    readonly property string artist: root.player ? root.player.trackArtist : ""

    function togglePlaying() {
        if (root.player && root.canTogglePlaying)
            root.player.togglePlaying();
    }
}
