pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "State.js" as State

Scope {
    id: root

    property bool enabled: false
    property string defaultProfile: "CH-Zurich"
    property var profileNames: ({})
    property bool monitorRunning: false
    property var profiles: null
    readonly property var activeProfiles: root.enabled ? (root.profiles || []).filter(profile => profile.path !== "") : []
    readonly property bool available: root.enabled && root.profiles !== null
    readonly property bool active: root.activeProfiles.length > 0
    readonly property string activeNames: root.activeProfiles.map(profile => profile.name).join(", ")
    readonly property string details: !root.available ? "Unavailable" : !root.active ? "Off" : root.activeProfiles.map(profile => {
        const name = Object.prototype.hasOwnProperty.call(root.profileNames, profile.name) ? root.profileNames[profile.name] : profile.name;
        return name + (profile.state === "activating" ? " (connecting)" : profile.state === "deactivating" ? " (disconnecting)" : "");
    }).join(", ")
    property bool busy: false
    property string actionError: ""
    property string statusError: ""
    readonly property string lastError: root.actionError || root.statusError

    property bool refreshPending: false
    property bool pendingToggle: false
    property string requestedProfile: ""
    property string requestOperation: ""
    property var targets: []
    property string operation: ""
    property bool queryForAction: false
    property bool queryCompletesAction: false
    property bool queryInvalid: false
    property string queryOutput: ""
    property string commandError: ""
    property int resultCode: -1

    function refresh(): void {
        if (!root.enabled)
            return;
        root.refreshPending = true;
        refreshDelay.restart();
    }

    function run(operation: string, arguments: var): void {
        root.operation = operation;
        root.resultCode = -1;
        root.commandError = "";
        command.exec({
            command: ["nmcli"].concat(arguments),
            environment: {
                LC_ALL: "C"
            }
        });
    }

    function query(): void {
        if (!root.enabled || !root.refreshPending || root.operation !== "")
            return;
        root.refreshPending = false;
        root.queryForAction = root.pendingToggle;
        root.pendingToggle = false;
        root.queryCompletesAction = root.busy && !root.queryForAction;
        root.queryOutput = "";
        root.queryInvalid = false;
        root.run("query", ["-t", "--escape", "yes", "-f", "NAME,UUID,TYPE,ACTIVE,STATE,ACTIVE-PATH", "connection", "show"]);
    }

    function toggle(): bool {
        if (!root.available || root.busy)
            return false;
        root.busy = true;
        root.actionError = "";
        root.requestedProfile = root.defaultProfile;
        root.pendingToggle = true;
        // Re-read before selecting a target; the displayed snapshot may be stale.
        root.refresh();
        return true;
    }

    function startNext(): void {
        if (!root.enabled || !root.busy) {
            root.targets = [];
            root.busy = false;
        } else if (root.targets.length) {
            const target = root.targets.shift();
            const down = root.requestOperation === "down";
            root.run(root.requestOperation, ["--wait", down ? "15" : "30", "connection", root.requestOperation, down ? "apath" : "uuid", target]);
            return;
        }
        root.refresh();
    }

    function finishCommand(): void {
        if (root.operation === "" || command.running)
            return;
        const operation = root.operation;
        root.operation = "";
        if (operation === "query") {
            const profiles = root.resultCode === 0 && !root.queryInvalid && root.enabled ? State.parseProfiles(root.queryOutput) : null;
            root.profiles = profiles;
            root.queryOutput = "";
            root.statusError = profiles !== null ? "" : "VPN status unavailable";
            if (root.queryForAction && root.busy) {
                if (profiles === null) {
                    root.busy = false;
                } else {
                    const request = State.selectRequest(profiles, root.requestedProfile);
                    root.actionError = request.error;
                    if (request.error) {
                        console.warn(request.error);
                        root.busy = false;
                    } else {
                        root.requestOperation = request.operation;
                        root.targets = request.targets;
                        root.startNext();
                    }
                }
            } else if (root.queryCompletesAction) {
                root.busy = false;
            }
        } else {
            if (root.resultCode !== 0 && root.busy) {
                root.actionError = root.commandError.trim() || "VPN request failed (exit " + root.resultCode + ")";
                console.warn(root.actionError);
            }
            root.startNext();
        }
        if (root.refreshPending)
            refreshDelay.restart();
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.profiles = null;
            root.queryInvalid = true;
            root.pendingToggle = false;
            root.targets = [];
            root.busy = false;
            root.refreshPending = false;
            refreshDelay.stop();
        }
    }
    Component.onCompleted: root.refresh()

    Timer {
        id: refreshDelay
        interval: 100
        onTriggered: root.query()
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.enabled && (!root.monitorRunning || !root.available)
        onTriggered: root.refresh()
    }

    Process {
        id: command
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            // Failed starts have no exited signal; defer until normal exit data is drained.
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.operation !== "query" || root.queryInvalid)
                    return;
                if (root.queryOutput.length + data.length > 262144) {
                    root.queryInvalid = true;
                    root.queryOutput = "";
                } else {
                    root.queryOutput += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.commandError = (root.commandError + data).slice(-1024)
        }
    }
}
