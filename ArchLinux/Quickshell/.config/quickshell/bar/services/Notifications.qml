import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    readonly property var dnd: dndState.value
    readonly property var hasHistory: historyState.value

    function openPanel() {
        Quickshell.execDetached(["qs", "-c", "command-center", "ipc", "call", "command-center", "toggle"]);
    }

    BooleanState {
        id: dndState
        propertyName: "dnd"
        signalName: "dndStateChanged"
    }

    BooleanState {
        id: historyState
        propertyName: "hasHistory"
        signalName: "historyStateChanged"
    }

    component BooleanState: Scope {
        id: stateRoot

        required property string propertyName
        required property string signalName
        property var value: null
        property int retryDelay: 2000
        property int revision: 0
        property int queryRevision: 0
        property bool queryPending: false
        property bool refreshPending: false
        property bool outputFinished: false
        property var exitCode: null

        function setState(text) {
            const value = text.trim();
            stateRoot.value = value === "true" ? true : value === "false" ? false : null;
            if (stateRoot.value === null)
                subscription.running = false;
            else
                stateRoot.retryDelay = 2000;
        }

        function refresh() {
            stateRoot.refreshPending = true;
            if (stateRoot.queryPending || queryProcess.running || !subscription.running)
                return;
            stateRoot.refreshPending = false;
            stateRoot.queryRevision = stateRoot.revision;
            stateRoot.outputFinished = false;
            stateRoot.exitCode = null;
            stateRoot.queryPending = true;
            watchdog.restart();
            queryProcess.running = true;
        }

        function finishQuery() {
            if (!stateRoot.queryPending || !stateRoot.outputFinished || stateRoot.exitCode === null)
                return;
            watchdog.stop();
            stateRoot.queryPending = false;
            // Signals and disconnects invalidate older query results.
            if (subscription.running && stateRoot.queryRevision === stateRoot.revision)
                stateRoot.setState(stateRoot.exitCode === 0 ? queryOutput.text : "");
            if (stateRoot.refreshPending && subscription.running)
                Qt.callLater(stateRoot.refresh);
        }

        Process {
            id: subscription
            command: ["qs", "-c", "command-center", "ipc", "listen", "notifications", stateRoot.signalName]
            running: true
            onStarted: stateRoot.refresh()

            stdout: SplitParser {
                onRead: data => {
                    if (!subscription.running)
                        return;
                    stateRoot.revision++;
                    stateRoot.setState(data);
                }
            }

            onRunningChanged: {
                if (!running) {
                    stateRoot.revision++;
                    stateRoot.value = null;
                    stateRoot.refreshPending = false;
                    restartTimer.interval = stateRoot.retryDelay;
                    stateRoot.retryDelay = Math.min(stateRoot.retryDelay * 2, 10000);
                    restartTimer.restart();
                }
            }
        }

        Process {
            id: queryProcess
            command: ["qs", "-c", "command-center", "ipc", "prop", "get", "notifications", stateRoot.propertyName]
            stdout: StdioCollector {
                id: queryOutput
                onStreamFinished: {
                    stateRoot.outputFinished = true;
                    stateRoot.finishQuery();
                }
            }
            // qmllint disable signal-handler-parameters
            onExited: function (exitCode) {
                stateRoot.exitCode = exitCode;
                stateRoot.finishQuery();
            }
            // qmllint enable signal-handler-parameters
            onRunningChanged: {
                if (!running && stateRoot.queryPending)
                    Qt.callLater(function () {
                        if (!queryProcess.running && stateRoot.queryPending && stateRoot.exitCode === null) {
                            stateRoot.exitCode = 1;
                            stateRoot.outputFinished = true;
                            stateRoot.finishQuery();
                        }
                    });
            }
        }

        Timer {
            id: watchdog
            interval: 5000
            repeat: false
            onTriggered: {
                if (stateRoot.queryRevision === stateRoot.revision)
                    stateRoot.setState("");
                stateRoot.queryRevision = -1;
                queryProcess.running = false;
            }
        }

        Timer {
            id: restartTimer
            interval: 2000
            repeat: false
            onTriggered: {
                if (!subscription.running)
                    subscription.running = true;
            }
        }
    }
}
