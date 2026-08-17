import QtQuick
import Quickshell.Services.Mpris

QtObject {
    readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? null

    readonly property var playbackState: player?.playbackState ?? MprisPlaybackState.Stopped

    readonly property bool active: player !== null

    readonly property bool canPause: player?.canPause ?? null
    readonly property bool canControl: player?.canControl ?? null

    readonly property string app: player?.identity ?? ""
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
}
