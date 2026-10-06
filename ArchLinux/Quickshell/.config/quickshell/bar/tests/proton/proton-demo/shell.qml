pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "proton" as Proton
import "proton/services" as ProtonServices

ShellRoot {
    id: root
    property var config: null
    property Core.Theme theme: Core.Theme {}
    FileView {
        path: (Quickshell.env("PROTON_FIXTURE_ROOT") || "/invalid-proton-fixture") + "/config.json"
        onLoaded: {
            try { root.config = JSON.parse(text()); }
            catch (_) { console.error("Invalid dummy config"); Qt.quit(); }
        }
        onLoadFailed: { console.error("Set PROTON_FIXTURE_ROOT to directory printed by tests/proton/proton-demo.py"); Qt.quit(); }
    }
    LazyLoader {
        id: serviceLoader
        active: root.config !== null
        ProtonServices.Service {
            config: root.config
            helperPath: Quickshell.shellPath("tests/proton/proton_demo_backend.py")
        }
    }
    LazyLoader {
        active: serviceLoader.item !== null && serviceLoader.item !== undefined && Quickshell.screens.length > 0
        Proton.Manager {
            theme: root.theme
            service: serviceLoader.item
            screen: Quickshell.screens[0]
            barRevealed: false
            visible: true
            onVisibleChanged: { if (!visible) Qt.quit(); }
        }
    }
}
