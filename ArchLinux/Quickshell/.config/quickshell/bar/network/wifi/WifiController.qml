import QtQuick
import Quickshell

import "./services" as Services

// Coordinates WiFi service state, menu state, models, timers, and user actions.
Scope {
    id: root

    readonly property int statusRefreshInterval: 5000
    readonly property int processTimeout: 20000
    readonly property int scanDebounceDelay: 500

    property bool menuVisible: false
    property bool isExpanded: false
    property alias isBusy: actionRunner.busy
    property alias scanRunning: scanner.scanRunning

    property alias wifiEnabled: statusService.wifiEnabled
    property alias activeConnectionUuid: statusService.activeConnectionUuid
    property alias currentSsid: statusService.currentSsid
    property alias currentSignalVal: statusService.currentSignal
    property alias currentIp: statusService.currentIp

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

    // Visibility is supplied explicitly by the overlay so startup refresh and
    // menu-open refresh remain separate, while close resets only original fields.
    function setMenuVisible(visible) {
        root.menuVisible = visible;
        if (visible) {
            root.refreshStatus();
            root.refreshSaved();
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
            scanner.scanRunning = false;
            scanDebounce.stop();
        }
    }

    function rescanNow() {
        if (root.isBusy || !root.wifiEnabled)
            return;
        root.clearScanModels();
        scanDebounce.restart();
    }

    function connectSaved(uuid, ssid) {
        root.pendingSavedUuid = uuid;
        root.pendingSavedSsid = ssid;
        actionRunner.connectSaved(uuid, ssid);
    }

    function setSavedPskAndConnect(uuid, password) {
        actionRunner.setSavedPskAndConnect(uuid, password);
    }

    // Personal saved profiles are activated unchanged. Enterprise profiles are
    // always rebuilt by the action service so fresh 802.1x credentials are used.
    function connectNew(ssid, password, username, isEnterprise) {
        if (!isEnterprise && savedNetworks.bySsid[ssid] !== undefined) {
            root.connectSaved(savedNetworks.bySsid[ssid].uuid, ssid);
            return;
        }

        root.pendingSavedUuid = "";
        root.pendingSavedSsid = ssid;
        actionRunner.connectNew(ssid, password, username, isEnterprise);
    }

    function toggleWifi() {
        if (root.isBusy)
            return;
        actionRunner.toggleWifi(root.wifiEnabled);
    }

    function disconnectNetwork() {
        if (root.isBusy)
            return;
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
            root.currentPage = 0;
        }
        onPasswordRequired: {
            processWatchdog.stop();
            root.errorVisible = false;
            root.setStatus("Password required", true);
            root.targetSsid = root.pendingSavedSsid;
            root.currentPage = 1;
            root.credentialsRequested(root.targetIsEnterprise);
        }
        onFailed: details => {
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
            if (root.isBusy || root.scanRunning)
                root.setStatus("Operation timed out - please wait", true);
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
}
