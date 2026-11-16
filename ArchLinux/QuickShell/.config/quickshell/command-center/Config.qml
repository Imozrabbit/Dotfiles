import QtQuick
import Quickshell
import Quickshell.Io
import "common/Config.js" as ConfigParser

Scope {
    id: root

    readonly property string localPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/command-center-local.json"
    property var settings: ConfigParser.resolveConfig("{}")

    FileView {
        id: localConfig
        path: root.localPath
        watchChanges: true
        printErrors: false
        onFileChanged: reloadDelay.restart()
        onLoaded: {
            const next = ConfigParser.resolveConfig(text(), root.settings);
            if (next === root.settings)
                console.warn("Invalid command-center-local.json; keeping last valid configuration");
            else
                root.settings = next;
        }
        // Missing/unreadable overrides retain defaults or the last live configuration.
        onLoadFailed: {}
    }

    Timer {
        id: reloadDelay
        interval: 150
        repeat: false
        onTriggered: localConfig.reload()
    }
}
