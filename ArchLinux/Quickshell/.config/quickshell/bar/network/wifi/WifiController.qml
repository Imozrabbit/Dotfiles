import QtQuick
import Quickshell
import Quickshell.Io

import "./services" as Services

// Coordinates WiFi service state, menu state, models, timers, and user actions.
Scope {
    id: root
    property var homeSsids: []
    property var dnsConfig: ({})
    property string lastHomeUuid: ""
    onHomeSsidsChanged: {
        root.lastHomeUuid = "";
        Qt.callLater(root.refreshStatus);
    }
    onDnsConfigChanged: {
        root.lastHomeUuid = "";
        Qt.callLater(root.refreshStatus);
    }

    readonly property int statusRefreshInterval: 1000
    readonly property int processTimeout: 20000
    readonly property int scanDebounceDelay: 500

    property bool menuVisible: false
    property bool isExpanded: false
    readonly property bool isBusy: actionRunner.busy || dnsService.busy
    property alias dns: dnsService
    property string newDnsSsid: ""
    property bool newDnsAwaitingStatus: false
    property var knownDnsUuids: []
    property string dnsPromptUuid: ""
    signal dnsChoiceRequested(string uuid)
    property alias scanRunning: scanner.scanRunning

    property alias wifiEnabled: statusService.wifiEnabled
    property alias activeConnectionUuid: statusService.activeConnectionUuid
    property alias currentSsid: statusService.currentSsid
    property alias currentSignalVal: statusService.currentSignal
    property alias currentIp: statusService.currentIp
    readonly property bool connectionReady: statusService.connected
    property bool wifiTogglePending: false
    property bool wifiToggleAwaitingCommand: false
    property bool wifiToggleTarget: false
    property int wifiToggleRefreshGeneration: 0
    readonly property bool wifiDisplayEnabled: root.wifiTogglePending ? root.wifiToggleTarget : root.wifiEnabled

    property string statusLine: ""
    property bool statusIsError: false
    property string errorText: ""
    property bool errorVisible: false

    property int currentPage: 0
    property string targetSsid: ""
    property bool targetIsEnterprise: false
    property string enteredUser: ""
    property string enteredPass: ""
    property string pendingSavedUuid: ""
    property string pendingSavedSsid: ""

    property alias savedModel: savedNetworks.model
    property alias networkModel: scanner.model
    property alias availableModel: availableNetworks

    signal credentialsRequested(bool focusUsername)
    signal dismissRequested

    function setStatus(message, bad) {
        root.statusLine = message;
        root.statusIsError = bad;
        statusTimer.restart();
    }

    function refreshStatus() {
        statusService.refresh();
    }

    function refreshSaved() {
        savedNetworks.refresh();
    }

    // Startup and menu opening refresh status and saved profiles; closing clears transient input.
    function setMenuVisible(visible) {
        root.menuVisible = visible;
        if (visible) {
            root.refreshStatus();
            root.refreshSaved();
            if (root.connectionReady && root.dnsPromptUuid === root.activeConnectionUuid)
                Qt.callLater(() => {
                    if (root.menuVisible && root.dnsPromptUuid !== "")
                        root.dnsChoiceRequested(root.dnsPromptUuid);
                });
        } else {
            root.currentPage = 0;
            root.targetSsid = "";
            root.enteredPass = "";
        }
    }

    // Saved and scan processes may finish in either order. Rebuilding after both
    // completion signals prevents a saved SSID from remaining in Available.
    function rebuildAvailableModel() {
        availableNetworks.clear();
        for (let i = 0; i < scanner.model.count; i++) {
            const item = scanner.model.get(i);
            if (savedNetworks.bySsid[item.ssid] !== undefined)
                continue;
            availableNetworks.append({
                ssid: item.ssid,
                security: item.security,
                strength: item.strength,
                isEnterprise: item.isEnterprise
            });
        }
    }

    function clearScanModels() {
        scanner.clear();
        root.rebuildAvailableModel();
    }

    function performScan() {
        if (!root.wifiEnabled) {
            root.setStatus("WiFi is off", true);
            return;
        }
        scanner.scan();
    }

    function startScanToggle() {
        if (root.isBusy)
            return;
        if (!root.wifiEnabled) {
            root.setStatus("WiFi is off", true);
            return;
        }

        if (!root.isExpanded) {
            root.isExpanded = true;
            root.currentPage = 0;
            root.clearScanModels();
            root.refreshSaved();
            scanDebounce.restart();
        } else {
            root.isExpanded = false;
            scanDebounce.stop();
        }
    }

    function rescanNow() {
        if (root.isBusy || !root.wifiEnabled)
            return;
        root.clearScanModels();
        scanDebounce.restart();
    }

    function connectSaved(uuid, ssid, isEnterprise) {
        if (root.isBusy)
            return;
        root.newDnsSsid = "";
        root.newDnsAwaitingStatus = false;
        root.pendingSavedUuid = uuid;
        root.pendingSavedSsid = ssid;
        root.targetIsEnterprise = isEnterprise === true;
        root.enteredUser = "";
        root.enteredPass = "";
        actionRunner.connectSaved(uuid);
    }

    function setSavedPskAndConnect(uuid, password) {
        actionRunner.setSavedPskAndConnect(uuid, password);
    }

    // Personal saved profiles are activated unchanged. Enterprise profiles are
    // always rebuilt by the action service so fresh 802.1x credentials are used.
    function connectNew(ssid, password, username, isEnterprise) {
        if (root.isBusy)
            return;
        if (!isEnterprise && savedNetworks.bySsid[ssid] !== undefined) {
            root.connectSaved(savedNetworks.bySsid[ssid].uuid, ssid, savedNetworks.bySsid[ssid].isEnterprise);
            return;
        }

        root.pendingSavedUuid = "";
        root.pendingSavedSsid = ssid;
        root.newDnsSsid = !isEnterprise && savedNetworks.bySsid[ssid] === undefined ? ssid : "";
        root.newDnsAwaitingStatus = false;
        root.knownDnsUuids = [];
        for (let i = 0; i < savedNetworks.model.count; i++)
            root.knownDnsUuids.push(savedNetworks.model.get(i).uuid);
        actionRunner.connectNew(ssid, password, username, isEnterprise);
    }

    function toggleWifi() {
        if (root.isBusy || root.wifiTogglePending)
            return;
        root.newDnsSsid = "";
        root.newDnsAwaitingStatus = false;
        root.dnsPromptUuid = "";
        root.wifiToggleTarget = !root.wifiEnabled;
        root.wifiTogglePending = true;
        root.wifiToggleAwaitingCommand = true;
        wifiToggleTimeout.restart();
        actionRunner.toggleWifi(root.wifiEnabled);
    }

    function disconnectNetwork() {
        if (root.isBusy)
            return;
        root.newDnsSsid = "";
        root.newDnsAwaitingStatus = false;
        root.dnsPromptUuid = "";
        actionRunner.disconnectNetwork(root.activeConnectionUuid);
    }

    // Route row intent through one place so saved, open, personal, and enterprise
    // networks retain their distinct activation and credential-page behavior.
    function selectNetwork(ssid, security, isEnterprise) {
        const securityText = String(security || "").trim();
        if (securityText === "" || securityText === "--") {
            root.pendingSavedUuid = "";
            root.pendingSavedSsid = ssid;
            root.connectNew(ssid, "", "", isEnterprise);
            return;
        }

        root.targetSsid = ssid;
        root.targetIsEnterprise = isEnterprise;
        root.enteredUser = "";
        root.enteredPass = "";
        root.pendingSavedUuid = "";
        root.pendingSavedSsid = ssid;
        root.currentPage = 1;
        root.credentialsRequested(root.targetIsEnterprise);
    }

    function submitCredentials() {
        if (root.pendingSavedUuid !== "" && !root.targetIsEnterprise)
            root.setSavedPskAndConnect(root.pendingSavedUuid, root.enteredPass);
        else
            root.connectNew(root.targetSsid, root.enteredPass, root.enteredUser, root.targetIsEnterprise);
    }

    function showNetworkList() {
        root.currentPage = 0;
    }

    function openAdvancedEditor() {
        actionRunner.openAdvancedEditor();
        root.dismissRequested();
    }

    ListModel {
        id: availableNetworks
    }

    Services.WifiDnsService {
        id: dnsService
        config: Object.assign({}, root.dnsConfig, {
            homeSsids: root.homeSsids
        })
        onSaved: uuid => {
            if (root.dnsPromptUuid === uuid)
                root.dnsPromptUuid = "";
        }
    }

    Services.WifiStatusService {
        id: statusService
    }

    Services.SavedNetworksService {
        id: savedNetworks

        onRefreshed: {
            root.rebuildAvailableModel();
        }
    }

    Services.WifiScanner {
        id: scanner

        onScanStarted: processWatchdog.restart()
        onScanCompleted: {
            processWatchdog.stop();
            root.rebuildAvailableModel();
            root.refreshSaved();
            if (scanner.model.count === 0 && savedNetworks.model.count === 0)
                root.setStatus("No networks found", true);
            else
                root.setStatus("Networks updated", false);
        }
        onScanFailed: {
            processWatchdog.stop();
            root.setStatus("Scan failed", true);
        }
    }

    Services.WifiActionRunner {
        id: actionRunner

        onStarted: {
            processWatchdog.restart();
            root.errorVisible = false;
            root.setStatus("Working…", false);
        }
        onSucceeded: {
            processWatchdog.stop();
            root.setStatus("Connected", false);
            root.errorVisible = false;
            root.enteredPass = "";
            root.currentPage = 0;
            if (root.newDnsSsid !== "") {
                root.newDnsAwaitingStatus = true;
                root.refreshStatus();
            }
        }
        onPasswordRequired: {
            processWatchdog.stop();
            root.errorVisible = false;
            root.enteredPass = "";
            root.setStatus("Password required", true);
            root.targetSsid = root.pendingSavedSsid;
            if (root.targetIsEnterprise) {
                root.setStatus("Use Advanced Settings for enterprise WiFi", true);
                root.currentPage = 0;
                return;
            }
            root.currentPage = 1;
            root.credentialsRequested(root.targetIsEnterprise);
        }
        onFailed: details => {
            root.newDnsSsid = "";
            root.newDnsAwaitingStatus = false;
            root.enteredPass = "";
            if (details === "Invalid connection" || details === "No active connection") {
                root.setStatus(details, true);
                return;
            }

            processWatchdog.stop();
            if (details.length > 0) {
                root.errorText = details;
                root.errorVisible = true;
            }
            root.setStatus("Connection failed", true);
        }
        onRefreshRequested: {
            root.refreshStatus();
            root.refreshSaved();
        }
        onRadioToggleSucceeded: {
            root.wifiToggleAwaitingCommand = false;
            root.wifiToggleRefreshGeneration = statusService.refresh();
            root.setStatus(root.wifiToggleTarget ? "Enabling WiFi…" : "Disabling WiFi…", false);
        }
        onRadioToggleFailed: details => {
            root.wifiTogglePending = false;
            root.wifiToggleAwaitingCommand = false;
            wifiToggleTimeout.stop();
            processWatchdog.stop();
            root.setStatus(details.length > 0 ? details : "WiFi toggle failed", true);
            root.refreshStatus();
        }
    }

    Connections {
        target: statusService

        function onRefreshed(generation) {
            if (root.connectionReady && root.homeSsids.includes(root.currentSsid) && root.activeConnectionUuid !== root.lastHomeUuid) {
                root.lastHomeUuid = root.activeConnectionUuid;
                if (root.activeConnectionUuid !== "")
                    dnsService.load(root.activeConnectionUuid);
            }
            if (!root.connectionReady || !root.homeSsids.includes(root.currentSsid))
                root.lastHomeUuid = "";
            if (!root.connectionReady || root.dnsPromptUuid !== root.activeConnectionUuid)
                root.dnsPromptUuid = "";
            if (root.newDnsAwaitingStatus && root.connectionReady && root.activeConnectionUuid !== "" && root.currentSsid === root.newDnsSsid) {
                root.newDnsAwaitingStatus = false;
                root.newDnsSsid = "";
                if (!root.knownDnsUuids.includes(root.activeConnectionUuid) && !root.homeSsids.includes(root.currentSsid)) {
                    root.dnsPromptUuid = root.activeConnectionUuid;
                    if (root.menuVisible)
                        root.dnsChoiceRequested(root.dnsPromptUuid);
                }
            }
            if (!root.wifiTogglePending || root.wifiToggleAwaitingCommand || generation < root.wifiToggleRefreshGeneration)
                return;
            if (root.wifiEnabled !== root.wifiToggleTarget)
                return;

            root.wifiTogglePending = false;
            root.wifiToggleAwaitingCommand = false;
            wifiToggleTimeout.stop();
            processWatchdog.stop();
            root.setStatus(root.wifiEnabled ? "WiFi enabled" : "WiFi disabled", false);
        }
    }

    Timer {
        id: statusTimer
        interval: 3200
        repeat: false
        onTriggered: root.statusLine = ""
    }

    // Scan and action processes intentionally share one watchdog. Starting either
    // restarts it, and either process completion stops it, matching monolith races.
    Timer {
        id: processWatchdog
        interval: root.processTimeout
        repeat: false
        onTriggered: {
            if (root.isBusy || root.scanRunning || root.wifiTogglePending)
                root.setStatus("Operation timed out - please wait", true);
        }
    }

    Timer {
        id: wifiToggleTimeout

        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.wifiTogglePending)
                return;
            root.wifiTogglePending = false;
            root.wifiToggleAwaitingCommand = false;
            root.setStatus("WiFi state confirmation timed out", true);
            root.refreshStatus();
        }
    }

    Timer {
        id: scanDebounce
        interval: root.scanDebounceDelay
        repeat: false
        onTriggered: root.performScan()
    }

    // Poll only while menu is visible and no scan or mutation is active.
    Timer {
        interval: root.statusRefreshInterval
        repeat: true
        running: root.menuVisible
        triggeredOnStart: false
        onTriggered: {
            if (!root.isBusy && !root.scanRunning)
                root.refreshStatus();
        }
    }

    Component.onCompleted: {
        root.refreshStatus();
        Qt.callLater(() => root.refreshSaved());
    }

    // Event-driven home enforcement also works when the Wi-Fi panel is closed.
    Process {
        id: networkMonitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: line => networkChanged.restart()
        }
        onRunningChanged: {
            if (!running)
                monitorRestart.restart();
        }
    }
    Timer {
        id: networkChanged
        interval: 500
        onTriggered: {
            root.lastHomeUuid = "";
            root.refreshStatus();
        }
    }
    Timer {
        id: monitorRestart
        interval: 5000
        onTriggered: {
            root.refreshStatus();
            networkMonitor.running = true;
        }
    }
}
