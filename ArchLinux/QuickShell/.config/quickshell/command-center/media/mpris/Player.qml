import QtQuick
import Quickshell
import Quickshell.Services.Mpris

QtObject {
    id: root

    required property var nativePlayer
    readonly property string name: root.nativePlayer?.identity ?? ""
    readonly property string desktopEntry: root.nativePlayer?.desktopEntry ?? ""
    readonly property string title: root.nativePlayer?.trackTitle ?? ""
    readonly property string artist: root.nativePlayer?.trackArtist ?? ""
    readonly property string artUrl: root.nativePlayer?.trackArtUrl ?? ""
    readonly property bool playing: root.nativePlayer?.isPlaying === true
    readonly property bool shuffle: root.nativePlayer?.shuffle === true
    readonly property int repeatMode: root.nativePlayer?.loopState === MprisLoopState.Playlist ? 1 : root.nativePlayer?.loopState === MprisLoopState.Track ? 2 : 0
    readonly property int trackKey: root.nativePlayer?.uniqueId ?? -1
    readonly property real duration: root.nativePlayer?.lengthSupported === true && Number.isFinite(root.nativePlayer.length) && root.nativePlayer.length > 0 ? root.nativePlayer.length : 0
    readonly property real progress: root.duration > 0 && root.nativePlayer?.positionSupported === true && Number.isFinite(root.nativePlayer.position) ? Math.max(0, Math.min(1, root.nativePlayer.position / root.duration)) : 0
    readonly property bool canGoPrevious: root.nativePlayer?.canGoPrevious === true
    readonly property bool canGoNext: root.nativePlayer?.canGoNext === true
    readonly property bool canTogglePlaying: root.nativePlayer?.canTogglePlaying === true
    readonly property bool canShuffle: root.nativePlayer?.canControl === true && root.nativePlayer.shuffleSupported === true
    readonly property bool canRepeat: root.nativePlayer?.canControl === true && root.nativePlayer.loopSupported === true
    // Desktop categories cover browser forks; native IDs cover missing desktop metadata.
    readonly property bool isBrowser: DesktopEntries.byId(root.desktopEntry)?.categories.includes("WebBrowser") === true || /(^|[.\s_-])(firefox|chromium|chrome|zen|brave|vivaldi|opera|edge|browser)(?=$|[.\s_-])/i.test(root.desktopEntry + " " + (root.nativePlayer?.dbusName ?? ""))
    readonly property bool canSeek: !root.isBrowser && root.nativePlayer?.canSeek === true && root.nativePlayer.positionSupported === true && root.duration > 0
}
