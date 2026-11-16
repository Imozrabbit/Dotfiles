pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "State.js" as State

Scope {
    id: root

    property bool enabled: false
    property var outputs: []
    property string targetId: ""
    property var displays: []
    readonly property var monitors: root.displays.filter(display => root.outputs.includes(display.connector))
    readonly property var target: root.monitors.find(display => display.id === root.targetId) ?? null
    property bool available: false
    property var readings: ({})
    readonly property real value: root.target ? root.readings[root.target.id] ?? 1 : 1
    property int maximum: 0
    property string actionError: ""
    property string statusError: ""
    property string discoveryError: ""
    readonly property string lastError: root.actionError || root.statusError || root.discoveryError
    readonly property bool busy: root.operation !== "" || root.discoverPending || root.readPending || root.pending !== null || root.candidate !== null
    signal discoveryFinished

    property int epoch: 0
    property int topology: 0
    property bool discoverPending: false
    property bool readPending: false
    property var pending: null
    property var candidate: null
    property string operation: ""
    property var job: null
    property string output: ""
    property bool outputInvalid: false
    property string commandError: ""
    property int resultCode: -1

    function capture(): var {
        return root.target ? {
            targetId: root.target.id,
            bus: root.target.bus,
            identity: root.target.identity,
            epoch: root.epoch
        } : null;
    }

    function current(job: var): bool {
        return root.enabled && !!root.target && !!job && job.epoch === root.epoch && job.targetId === root.target.id && job.bus === root.target.bus && job.identity === root.target.identity;
    }

    function discover(): void {
        if (!root.enabled || (root.operation === "discover" && root.job.topology === root.topology))
            return;
        root.discoverPending = true;
        Qt.callLater(root.work);
    }

    function refresh(): void {
        if (!root.enabled || !root.target || (root.operation === "query" && root.current(root.job)))
            return;
        root.readPending = true;
        Qt.callLater(root.work);
    }

    function setValue(value: real): bool {
        if (!root.enabled || !root.available || !root.target || !isFinite(value))
            return false;
        const request = root.capture();
        request.percent = Math.max(1, Math.min(100, value));
        root.pending = request;
        root.actionError = "";
        writeDelay.start();
        return true;
    }

    function run(operation: string, args: var, job: var): void {
        root.operation = operation;
        root.job = job;
        root.resultCode = -1;
        root.output = "";
        root.outputInvalid = false;
        root.commandError = "";
        command.exec({
            command: ["ddcutil"].concat(args),
            environment: {
                LC_ALL: "C"
            }
        });
        commandTimeout.restart();
    }

    function work(): void {
        if (!root.enabled || root.operation !== "")
            return;
        if (root.discoverPending) {
            root.discoverPending = false;
            root.run("discover", ["detect", "--brief"], {
                topology: root.topology
            });
        } else if (root.candidate) {
            const request = root.candidate;
            root.candidate = null;
            const raw = State.rawValue(request.percent, root.maximum);
            if (root.current(request) && raw !== null)
                root.run("set", ["--bus", String(request.bus), "setvcp", "10", String(raw)], request);
        } else if (root.readPending) {
            root.readPending = false;
            if (root.target)
                root.run("query", ["--bus", String(root.target.bus), "--brief", "getvcp", "10"], root.capture());
        } else if (root.pending && !writeDelay.running) {
            const request = root.pending;
            root.pending = null;
            if (root.available && root.current(request))
                root.run("verify", ["detect", "--brief"], request);
        }
    }

    function finishCommand(): void {
        if (root.operation === "" || command.running)
            return;
        commandTimeout.stop();
        const operation = root.operation;
        const job = root.job;
        const success = root.resultCode === 0 && !root.outputInvalid;
        root.operation = "";
        if (operation === "discover" && root.enabled && job.topology === root.topology) {
            const displays = success ? State.parseDisplays(root.output) : null;
            if (displays !== null) {
                const stable = displays.map(display => root.displays.find(old => JSON.stringify(old) === JSON.stringify(display)) ?? display);
                if (JSON.stringify(stable) !== JSON.stringify(root.displays))
                    root.displays = stable;
                root.discoveryError = "";
            } else {
                root.displays = [];
                root.discoveryError = root.commandError.trim() || "Monitor discovery unavailable";
            }
            root.discoveryFinished();
        } else if (operation === "verify" && root.current(job)) {
            const displays = success ? State.parseDisplays(root.output) : null;
            if (displays && displays.some(display => display.id === job.targetId && display.bus === job.bus)) {
                root.candidate = job;
            } else {
                root.available = false;
                root.pending = null;
                root.statusError = root.commandError.trim() || "Monitor connection changed or unavailable";
                root.discoverPending = true;
            }
        } else if (operation === "query" && root.current(job)) {
            const reading = success ? State.parseValue(root.output) : null;
            root.available = reading !== null;
            if (reading) {
                const readings = Object.assign({}, root.readings);
                readings[job.targetId] = reading.value;
                root.readings = readings;
                root.maximum = reading.maximum;
                root.statusError = "";
            } else {
                root.pending = null;
                root.statusError = root.commandError.trim() || "Monitor brightness unavailable";
            }
        } else if (operation === "set" && root.current(job)) {
            if (!success) {
                root.pending = null;
                root.actionError = root.commandError.trim() || "Monitor brightness request failed (exit " + root.resultCode + ")";
                console.warn(root.actionError);
            }
            root.readPending = true;
        }
        root.output = "";
        if (root.discoverPending || root.readPending || root.pending || root.candidate)
            Qt.callLater(root.work);
    }

    onMonitorsChanged: {
        const readings = {};
        for (const monitor of root.monitors) {
            if (root.readings[monitor.id] !== undefined)
                readings[monitor.id] = root.readings[monitor.id];
        }
        root.readings = readings;
    }
    onTargetChanged: {
        ++root.epoch;
        root.pending = null;
        root.candidate = null;
        writeDelay.stop();
        root.available = false;
        root.maximum = 0;
        root.actionError = "";
        root.statusError = "";
        root.readPending = root.enabled && !!root.target;
        if (root.readPending)
            Qt.callLater(root.work);
    }
    onOutputsChanged: {
        ++root.topology;
        root.discover();
    }
    onEnabledChanged: {
        ++root.topology;
        ++root.epoch;
        root.available = false;
        root.pending = null;
        root.candidate = null;
        writeDelay.stop();
        root.readPending = false;
        root.discoverPending = false;
        if (root.enabled) {
            root.discover();
            root.refresh();
        }
    }
    Component.onCompleted: root.discover()

    Timer {
        id: writeDelay
        interval: 150
        onTriggered: root.work()
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.enabled && (!!root.target || root.discoveryError !== "")
        onTriggered: root.target ? root.refresh() : root.discover()
    }
    Timer {
        id: commandTimeout
        interval: 10000
        onTriggered: {
            root.commandError = "DDC command timed out";
            command.running = false;
        }
    }
    Process {
        id: command
        onExited: (exitCode, exitStatus) => root.resultCode = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (!running && root.operation !== "")
                Qt.callLater(root.finishCommand);
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                if (root.operation === "set" || root.outputInvalid)
                    return;
                const limit = root.operation === "query" ? 256 : 65536;
                if (root.output.length + data.length > limit) {
                    root.outputInvalid = true;
                    root.output = "";
                } else {
                    root.output += data;
                }
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root.commandError = (root.commandError + data).slice(0, 1024)
        }
    }
}
