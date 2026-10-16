import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var profiles: ({})
    property bool busy: false
    property string requestUuid: ""
    property int exitCode: -1
    property bool outputDone: false
    property bool errorDone: false
    property int generation: 0
    property bool timedOut: false
    property var config: ({})
    readonly property string configJson: JSON.stringify(root.config)
    property var providers: []
    property string configWarning: ""
    property bool ready: false
    property bool configurePending: true
    property var readQueue: []
    property string action: "read"
    property string testProvider: ""
    property string requestConfig: ""
    readonly property string preferredProvider: root.providers.some(provider => provider.id === root.config.preferredProvider) ? root.config.preferredProvider : root.providers[0]?.id || "automatic"
    onConfigJsonChanged: {
        root.configurePending = true;
        root.ready = false;
        Qt.callLater(root.drain);
    }
    Component.onCompleted: root.drain()
    signal saved(string uuid)

    function update(uuid, data) {
        const next = Object.assign({}, root.profiles);
        next[uuid] = data;
        root.profiles = next;
    }
    function load(uuid) {
        if (!uuid || root.busy && root.action === "read" && root.requestUuid === uuid && root.requestConfig === root.configJson)
            return;
        if (!root.readQueue.includes(uuid))
            root.readQueue = root.readQueue.concat([uuid]);
        if (!root.ready && !root.busy)
            root.configurePending = true;
        root.drain();
    }
    function save(uuid, policy) {
        if (policy === "automatic" || root.providers.some(provider => provider.id === policy))
            root.run(uuid, policy);
    }
    function test(uuid, provider) {
        root.run(uuid, provider, "test");
    }
    function drain() {
        if (root.busy || query.running)
            return;
        if (root.configurePending) {
            root.configurePending = false;
            root.run("configuration", "", "configure");
        } else if (root.ready && root.readQueue.length) {
            const uuid = root.readQueue[0];
            root.readQueue = root.readQueue.slice(1);
            root.run(uuid, "");
        }
    }
    function run(uuid, policy, operation) {
        if (root.busy || query.running || !uuid)
            return;
        const action = operation || (policy ? "save" : "read");
        if (action !== "configure" && !root.ready)
            return;
        root.action = action;
        root.requestConfig = root.configJson;
        root.testProvider = action === "test" ? policy : "";
        root.requestUuid = uuid;
        root.generation++;
        root.exitCode = -1;
        root.timedOut = false;
        root.outputDone = false;
        root.errorDone = false;
        root.busy = true;
        root.update(uuid, Object.assign({}, root.profiles[uuid] || {}, {
            message: action === "test" ? "Testing every server…" : policy ? "Saving…" : "Loading…",
            error: false
        }));
        const args = action === "configure" ? ["configure"] : action === "test" ? ["test", policy] : [action, uuid].concat(policy ? [policy] : []);
        query.command = ["python3", Quickshell.shellPath("network/wifi/scripts/dns.py")].concat(args, [root.requestConfig]);
        watchdog.restart();
        query.running = true;
    }
    function finish() {
        if (!root.busy || root.exitCode < 0 || !root.outputDone || !root.errorDone)
            return;
        watchdog.stop();
        if (root.timedOut)
            root.exitCode = 1;
        root.busy = false;
        Qt.callLater(root.drain);
        let data = null;
        try {
            data = JSON.parse(output.text);
        } catch (_) {}
        if (root.requestConfig !== root.configJson)
            return;
        if (root.action === "configure") {
            root.providers = root.exitCode === 0 && Array.isArray(data?.providers) ? data.providers : [];
            root.configWarning = root.exitCode === 0 && Array.isArray(data?.warnings) ? data.warnings.join("\n") : "DNS provider configuration unavailable; reopen card to retry";
            root.profiles = ({});
            root.ready = root.exitCode === 0;
            return;
        }
        if (root.action === "test" && root.exitCode === 0 && data?.provider === root.testProvider && Array.isArray(data.results)) {
            root.update(root.requestUuid, Object.assign({}, root.profiles[root.requestUuid], {
                error: false,
                message: data.results.map(result => result.server + ": " + result.status + " — " + result.detail).join("\n")
            }));
            return;
        }
        if (root.exitCode !== 0 || !data || data.uuid !== root.requestUuid || !["automatic", "custom"].concat(root.providers.map(provider => provider.id)).includes(data.policy)) {
            root.update(root.requestUuid, Object.assign({}, root.profiles[root.requestUuid] || {}, {
                policy: root.action === "test" ? root.profiles[root.requestUuid]?.policy || "" : "",
                message: root.timedOut ? "DNS operation timed out; reopen card to reload" : errors.text.trim().slice(0, 200) || "DNS operation failed; reopen card to reload",
                error: true
            }));
            return;
        }
        const messages = {
            applied: "Saved and applied",
            "next-connection": "Saved for next connection",
            "saved-not-applied": "Saved; live apply unavailable. Reconnect when convenient."
        };
        root.update(root.requestUuid, {
            policy: data.policy,
            home: data.home === true,
            error: false,
            message: data.home ? "Home: router DNS only" + (data.application ? ". " + messages[data.application] : "") : root.action === "save" ? messages[data.application] || "Saved" : data.policy === "custom" ? "Custom DNS — preserved until you choose" : ""
        });
        if (root.action === "save")
            root.saved(root.requestUuid);
    }
    Process {
        id: query
        stdout: StdioCollector {
            id: output
            onStreamFinished: {
                root.outputDone = true;
                root.finish();
            }
        }
        stderr: StdioCollector {
            id: errors
            onStreamFinished: {
                root.errorDone = true;
                root.finish();
            }
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.exitCode = exitCode;
            root.finish();
        }
        // qmllint enable signal-handler-parameters
        onRunningChanged: {
            const generation = root.generation;
            if (!running)
                Qt.callLater(root.drain);
            if (!running && root.busy)
                Qt.callLater(function () {
                    if (root.busy && root.generation === generation && root.exitCode < 0) {
                        root.exitCode = 1;
                        root.outputDone = true;
                        root.errorDone = true;
                        root.finish();
                    }
                });
        }
    }
    Timer {
        id: watchdog
        interval: 75000
        onTriggered: {
            // Keep ownership until exit and both streams finish; never reuse a
            // process while old output could be attributed to a new request.
            root.timedOut = true;
            query.running = false;
        }
    }
}
