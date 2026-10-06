import QtQuick
import Quickshell
import Quickshell.Io
import "State.js" as State

Scope {
    id: root
    required property var config
    property string helperPath: Quickshell.shellPath("proton/backend.py")
    property var state: State.emptyState()
    readonly property var snapshot: state.snapshot
    readonly property var confirmation: state.confirmation
    readonly property var progress: state.progress
    readonly property var messages: state.messages
    property bool busy: false
    property string requestId: ""
    property string requestArea: "updates"
    property var command: []
    property bool outputFinished: false
    property bool errorFinished: false
    property bool exited: false
    property int exitCode: -1
    property bool invalidOutput: false
    property int sequence: 0
    property double lastAutomaticRefresh: 0
    property string currentAction: ""
    property int outputOffset: 0

    function request(action, payload) {
        if (root.busy) return false;
        root.requestId = "proton-" + Date.now() + "-" + (++root.sequence);
        root.requestArea = ["remove", "prepareRemove"].includes(action) ? "installed" : ["selectGe", "syncGe"].includes(action) ? "selection" : "updates";
        root.currentAction = action;
        root.state = State.beginRequest(root.state, action === "refresh");
        root.outputFinished = false;
        root.errorFinished = false;
        root.exited = false;
        root.exitCode = -1;
        root.invalidOutput = false;
        root.outputOffset = 0;
        root.command = ["python3", root.helperPath, "--request", JSON.stringify({ id: root.requestId, action: action, config: root.config, payload: payload || {} })];
        root.busy = true;
        helper.running = true;
        return true;
    }
    function inspect() { return request("inspect"); }
    // ponytail: cooldown lasts for this shared service lifetime; persist cached results only if shell restarts cause excessive repeat checks.
    function open() {
        return Date.now() - root.lastAutomaticRefresh >= 86400000 ? request("refresh") : inspect();
    }
    function refresh() { return request("refresh"); }
    function prepareInstall(family) { return request("prepareInstall", { family: family }); }
    function prepareRemove(name) { return request("prepareRemove", { name: name }); }
    function confirm(descriptor) {
        if (!State.confirmation(descriptor)) return false;
        return request(descriptor.action, descriptor);
    }
    function selectGe(name) { return request("selectGe", { name: name }); }
    function syncGe() { return request("syncGe"); }
    function readOutput(text) {
        if (text.length > 8 * 1024 * 1024) { root.invalidOutput = true; return; }
        let end = text.indexOf("\n", root.outputOffset);
        while (end >= 0) {
            const event = State.parseEvent(text.slice(root.outputOffset, end), root.requestId);
            if (!event || root.state.finished) root.invalidOutput = true;
            else root.state = State.applyEvent(root.state, event);
            root.outputOffset = end + 1;
            end = text.indexOf("\n", root.outputOffset);
        }
    }
    function finish() {
        if (!root.busy || !root.exited || !root.outputFinished || !root.errorFinished) return;
        if (!root.state.finished || root.invalidOutput || root.exitCode !== 0) {
            const next = Object.assign({}, root.state);
            next.confirmation = null;
            next.messages = Object.assign({}, root.state.messages);
            next.messages[root.requestArea] = [{ severity: "error", text: "Proton helper failed or returned invalid output." + (errors.text.trim() ? " " + errors.text.trim().slice(0, 500) : "") }];
            next.finished = true;
            root.state = next;
        }
        if (root.currentAction === "refresh") root.lastAutomaticRefresh = Date.now();
        root.busy = false;
    }
    Process {
        id: helper
        command: root.command
        stdout: StdioCollector {
            waitForEnd: false
            onTextChanged: root.readOutput(text)
            onStreamFinished: {
                root.readOutput(text);
                if (root.outputOffset !== text.length) root.invalidOutput = true;
                root.outputFinished = true;
                root.finish();
            }
        }
        stderr: StdioCollector {
            id: errors
            onStreamFinished: { root.errorFinished = true; root.finish(); }
        }
        // qmllint disable signal-handler-parameters
        onExited: function (exitCode) {
            root.exitCode = exitCode;
            root.exited = true;
            root.finish();
        }
        // qmllint enable signal-handler-parameters
    }
}
