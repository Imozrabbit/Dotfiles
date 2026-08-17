import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property string currentMethod: ""
    readonly property var methodOrder: ["keyboard-us", "keyboard-fr", "rime"]

    function isKnownMethod(name) {
        return root.methodOrder.indexOf(name) !== -1;
    }

    function refresh() {
        if (!queryProcess.running)
            queryProcess.running = true;
    }

    function cycle() {
        if (switchProcess.running)
            return;

        const currentIndex = root.methodOrder.indexOf(root.currentMethod);
        const nextIndex = (currentIndex + 1) % root.methodOrder.length;

        switchProcess.command = ["fcitx5-remote", "-s", root.methodOrder[nextIndex]];
        switchProcess.running = true;
    }

    Process {
        id: queryProcess
        command: ["fcitx5-remote", "-n"]
        stdout: SplitParser {
            onRead: data => {
                const method = data.trim();
                if (root.isKnownMethod(method))
                    root.currentMethod = method;
            }
        }
    }

    Process {
        id: switchProcess
        onRunningChanged: {
            if (!running)
                root.refresh();
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
