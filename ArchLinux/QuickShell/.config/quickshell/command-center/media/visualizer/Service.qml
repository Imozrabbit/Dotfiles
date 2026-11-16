pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

Scope {
    id: root

    property bool enabled: false
    property string outputName: ""
    property var levels: []
    readonly property bool running: cava.running
    readonly property string cacheDirectory: Quickshell.cachePath("media-visualizer")
    readonly property string configPath: root.cacheDirectory + "/config"
    readonly property string desiredConfig: root.enabled ? Protocol.configuration(root.outputName) || "" : ""

    property string savedConfig: ""
    property string pendingConfig: ""
    property bool startPending: false
    property bool acceptingFrames: false
    property string frameBuffer: ""
    property bool discardingFrame: false

    function clear(): void {
        root.acceptingFrames = false;
        root.levels = [];
        root.frameBuffer = "";
        root.discardingFrame = false;
    }

    function synchronize(): void {
        if (!root.startPending || root.pendingConfig !== "" || cava.running)
            return;
        if (root.savedConfig !== root.desiredConfig) {
            root.pendingConfig = root.desiredConfig;
            configFile.setText(root.pendingConfig);
            return;
        }
        root.startPending = false;
        root.acceptingFrames = true;
        cava.exec({
            command: ["cava", "-p", root.configPath],
            environment: {
                XDG_CONFIG_HOME: root.cacheDirectory
            }
        });
    }

    function readChunk(data: string): void {
        if (!root.acceptingFrames)
            return;
        let start = 0;
        while (start < data.length) {
            const end = data.indexOf("\n", start);
            const stop = end < 0 ? data.length : end;
            if (!root.discardingFrame) {
                if (root.frameBuffer.length + stop - start > 80) {
                    root.frameBuffer = "";
                    root.discardingFrame = true;
                    root.levels = [];
                } else {
                    root.frameBuffer += data.slice(start, stop);
                }
            }
            if (end < 0)
                return;
            if (!root.discardingFrame)
                root.levels = Protocol.parseFrame(root.frameBuffer) || [];
            root.frameBuffer = "";
            root.discardingFrame = false;
            start = end + 1;
        }
    }

    onDesiredConfigChanged: {
        root.clear();
        root.startPending = root.desiredConfig !== "";
        cava.running = false;
        Qt.callLater(root.synchronize);
    }
    Component.onCompleted: {
        root.startPending = root.desiredConfig !== "";
        Qt.callLater(root.synchronize);
    }

    FileView {
        id: configFile
        path: root.configPath
        preload: false
        atomicWrites: true
        printErrors: false
        onSaved: {
            root.savedConfig = root.pendingConfig;
            root.pendingConfig = "";
            Qt.callLater(root.synchronize);
        }
        onSaveFailed: {
            if (root.desiredConfig === root.pendingConfig)
                root.startPending = false;
            root.savedConfig = "";
            console.warn("CAVA config write failed; spectrum unavailable");
            // Reset retained failed data only after FileView finishes its callback.
            Qt.callLater(() => {
                configFile.path = "";
                configFile.path = root.configPath;
                root.pendingConfig = "";
                root.synchronize();
            });
        }
    }

    Process {
        id: cava
        onRunningChanged: {
            if (!running) {
                root.clear();
                Qt.callLater(root.synchronize);
            }
        }
        stdout: SplitParser {
            // Native newline buffering is unbounded; assemble limited frames above.
            splitMarker: ""
            onRead: data => root.readChunk(data)
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: {}
        }
    }
}
